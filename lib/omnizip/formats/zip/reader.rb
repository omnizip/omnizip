# frozen_string_literal: true

require "fileutils"

module Omnizip
  module Formats
    module Zip
      # ZIP archive reader
      class Reader
        include Omnizip::Formats::Zip::Constants

        attr_reader :file_path

        def initialize(file_path)
          @file_path = file_path
          @entries = []
          @central_directory = []
        end

        # Read and parse the ZIP archive
        def read
          File.open(file_path, "rb") do |io|
            read_from_io(io)
          end
          self
        end

        # Read from an IO object
        def read_from_io(io)
          # Find and read End of Central Directory
          eocd = EndOfCentralDirectory.find_in_file(io)

          # Read Central Directory
          read_central_directory(io, eocd)

          self
        end

        # All entries, parsing on first use — a Reader is usable
        # immediately; #read remains for explicit eager loading
        def entries
          ensure_read
          @entries
        end

        # Extract all files to a directory
        def extract_all(output_dir, preserve_links: true,
dereference_links: false)
          entries.each do |entry|
            extract_entry(entry, output_dir, preserve_links: preserve_links,
                                             dereference_links: dereference_links)
          end
        end

        # Extract a specific entry
        def extract_entry(entry, output_dir, preserve_links: true,
dereference_links: false)
          output_path = File.join(output_dir, entry.filename)

          if entry.directory?
            FileUtils.mkdir_p(output_path)
          elsif preserve_links && !dereference_links && entry.symlink?
            extract_symlink(entry, output_dir)
          else
            FileUtils.mkdir_p(File.dirname(output_path))

            decompressed_data = read_entry_data(entry)

            # Write decompressed data
            File.binwrite(output_path, decompressed_data)

            # Set file permissions if Unix
            if entry.unix_permissions.positive?
              File.chmod(entry.unix_permissions & 0o777, output_path)
            end
          end
        end

        # Extract a symbolic link
        def extract_symlink(entry, output_dir)
          output_path = File.join(output_dir, entry.filename)

          unless LinkHandler.symlink_supported?
            warn "Warning: Symbolic links not supported on #{RUBY_PLATFORM}, extracting as regular file"
            extract_entry(entry, output_dir, preserve_links: false)
            return
          end

          target = entry.link_target
          unless target
            warn "Warning: No link target found for #{entry.filename}, skipping"
            return
          end

          FileUtils.mkdir_p(File.dirname(output_path))

          # Remove existing file/link if present
          FileUtils.rm_f(output_path) if File.exist?(output_path) || File.symlink?(output_path)

          LinkHandler.create_symlink(target, output_path)
        end

        # List all entries in the archive
        def list_entries(show_links: false)
          entries.map do |entry|
            info = {
              filename: entry.filename,
              compressed_size: entry.compressed_size,
              uncompressed_size: entry.uncompressed_size,
              compression_method: compression_method_name(entry.compression_method),
              crc32: entry.crc32,
              directory: entry.directory?,
            }

            if show_links && entry.symlink?
              info[:symlink] = true
              info[:link_target] = entry.link_target
            end

            info
          end
        end

        # Decompress +compressed_data+ according to +method+. Public API
        # for callers (e.g., ParallelExtractor) that hold raw compressed
        # payload outside an entry stream.
        #
        # @param compressed_data [String] Compressed bytes
        # @param method [Integer] ZIP compression method code
        # @param uncompressed_size [Integer] Expected uncompressed size
        # @return [String] Decompressed bytes
        def decompress(compressed_data, method, uncompressed_size)
          decompress_data(compressed_data, method, uncompressed_size)
        end

        # Read an entry's decompressed content into a String.
        # Directory entries return an empty string; symlinks return
        # their target path.
        #
        # @param entry_name [String] Name of the entry to read
        # @return [String] Decompressed content
        # @raise [RuntimeError] if the entry is not found
        def read_entry(entry_name)
          ensure_read
          entry = @entries.find { |e| e.filename == entry_name }
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

          return "" if entry.directory?
          return entry.link_target if entry.symlink?

          read_entry_data(entry)
        end

        # Stream a single entry's decompressed content in +chunk_size+
        # chunks, yielding each. STORE copies raw bytes and DEFLATE
        # feeds an incremental inflater, so memory stays bounded by
        # the chunk size; methods without an incremental decoder fall
        # back to the whole-entry read (yielded as one chunk). The
        # streamed path verifies the entry CRC after the last chunk.
        #
        # @param entry_name [String] Name of the entry to stream
        # @param chunk_size [Integer] Read granularity in bytes
        # @yield [chunk] Decompressed chunk
        # @return [void]
        def read_entry_stream(entry_name, chunk_size: 64 * 1024, &block)
          ensure_read
          entry = @entries.find { |e| e.filename == entry_name }
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry
          return if entry.directory? || entry.symlink?

          crc = Omnizip::Checksums::Crc32.new
          streamed =
            File.open(file_path, "rb") do |io|
              io.seek(entry_data_offset(io, entry), ::IO::SEEK_SET)

              # Bound reads by the entry payload — what follows it in
              # the file is the central directory, not entry data
              remaining = entry.compressed_size

              case entry.compression_method
              when COMPRESSION_STORE
                stream_raw(io, chunk_size, crc, remaining, &block)
              when COMPRESSION_DEFLATE
                stream_deflate(io, chunk_size, crc, remaining, &block)
              else
                yield(read_entry_data(entry))
                false
              end
            end

          return unless streamed

          if crc.finalize != entry.crc32
            raise Omnizip::ChecksumError,
                  "CRC mismatch for #{entry.filename}"
          end
        end

        private

        def stream_raw(io, chunk_size, crc, remaining)
          while remaining.positive? &&
              (chunk = io.read([chunk_size, remaining].min))
            break if chunk.empty?

            remaining -= chunk.bytesize
            crc.update(chunk)
            yield chunk
          end
          true
        end

        def stream_deflate(io, chunk_size, crc, remaining, &block)
          require "zlib"
          inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
          begin
            while remaining.positive? &&
                (chunk = io.read([chunk_size, remaining].min))
              break if chunk.empty?

              remaining -= chunk.bytesize
              emit_inflated(inflater.inflate(chunk), crc, &block)
            end
            emit_inflated(inflater.finish, crc, &block)
          ensure
            inflater.close
          end
          true
        end

        def emit_inflated(out, crc)
          return if out.nil? || out.empty?

          crc.update(out)
          yield out
        end

        # Decompress and CRC-verify a single entry's data
        def read_entry_data(entry)
          File.open(file_path, "rb") do |io|
            io.seek(entry_data_offset(io, entry), ::IO::SEEK_SET)

            compressed_data = io.read(entry.compressed_size)
            decompressed_data = decompress_data(
              compressed_data,
              entry.compression_method,
              entry.uncompressed_size,
            )

            calculated_crc = Omnizip::Checksums::Crc32.new.tap do |c|
              c.update(decompressed_data)
            end.finalize
            if calculated_crc != entry.crc32
              raise Omnizip::ChecksumError,
                    "CRC mismatch for #{entry.filename}"
            end

            decompressed_data
          end
        end

        # File offset of an entry's compressed payload: the local
        # header's fixed 30 bytes plus its filename/extra fields.
        def entry_data_offset(io, entry)
          io.seek(entry.local_header_offset, ::IO::SEEK_SET)

          fixed_header = io.read(30)
          _signature, _version, _flags, _method, _time, _date, _crc32,
          _comp_size, _uncomp_size, filename_length, extra_length = fixed_header.unpack("VvvvvvVVVvv")

          io.read(filename_length + extra_length)
          io.pos
        end

        # Parse the central directory once, on demand
        def ensure_read
          read if @entries.empty? && @central_directory.empty?
        end

        # Read central directory entries
        def read_central_directory(io, eocd)
          io.seek(eocd.central_directory_offset, ::IO::SEEK_SET)

          eocd.total_entries.times do
            header_data = io.read(46)
            break unless header_data && header_data.size == 46

            # Get dynamic field lengths
            _, _, _, _, _, _, _, _, _, _,
            filename_length, extra_field_length, comment_length = header_data.unpack("VvvvvvvVVVvvv")

            # Read complete header
            complete_data = header_data + io.read(filename_length + extra_field_length + comment_length)
            entry = CentralDirectoryHeader.from_binary(complete_data)

            @entries << entry
            @central_directory << entry
          end
        end

        # Decompress data based on compression method
        def decompress_data(compressed_data, method, uncompressed_size)
          case method
          when COMPRESSION_STORE
            compressed_data
          when COMPRESSION_DEFLATE
            decompress_deflate(compressed_data)
          when COMPRESSION_BZIP2
            decompress_bzip2(compressed_data)
          when COMPRESSION_LZMA
            decompress_lzma(compressed_data, uncompressed_size)
          when COMPRESSION_ZSTANDARD
            decompress_zstandard(compressed_data)
          else
            raise Omnizip::UnsupportedFormatError,
                  "Unsupported compression method: #{method}"
          end
        end

        # Decompress using Deflate
        def decompress_deflate(data)
          require "zlib"
          # ZIP uses raw deflate without zlib wrapper
          Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data)
        rescue StandardError => e
          raise Omnizip::DecompressionError,
                "Deflate decompression failed: #{e.message}"
        end

        # Decompress using BZip2
        def decompress_bzip2(data)
          algorithm = AlgorithmRegistry.get(:bzip2)
          algorithm.decompress(data)
        rescue StandardError => e
          raise Omnizip::DecompressionError,
                "BZip2 decompression failed: #{e.message}"
        end

        # Decompress using LZMA
        def decompress_lzma(data, uncompressed_size)
          algorithm = AlgorithmRegistry.get(:lzma)
          algorithm.decompress(data, uncompressed_size: uncompressed_size)
        rescue StandardError => e
          raise Omnizip::DecompressionError,
                "LZMA decompression failed: #{e.message}"
        end

        # Decompress using Zstandard
        def decompress_zstandard(data)
          algorithm = AlgorithmRegistry.get(:zstandard)
          algorithm.decompress(data)
        rescue StandardError => e
          raise Omnizip::DecompressionError,
                "Zstandard decompression failed: #{e.message}"
        end

        # Get human-readable compression method name
        def compression_method_name(method)
          case method
          when COMPRESSION_STORE then "Store"
          when COMPRESSION_DEFLATE then "Deflate"
          when COMPRESSION_BZIP2 then "BZip2"
          when COMPRESSION_LZMA then "LZMA"
          when COMPRESSION_ZSTANDARD then "Zstandard"
          else "Unknown (#{method})"
          end
        end
      end
    end
  end
end
