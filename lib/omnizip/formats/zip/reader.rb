# frozen_string_literal: true

require_relative "constants"
require_relative "local_file_header"
require_relative "central_directory_header"
require_relative "end_of_central_directory"
require_relative "unix_extra_field"
require_relative "../../link_handler"

module Omnizip
  module Formats
    module Zip
      # ZIP archive reader
      class Reader
        include Constants

        attr_reader :file_path, :entries

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

            File.open(file_path, "rb") do |io|
              # Seek to local file header
              io.seek(entry.local_header_offset, ::IO::SEEK_SET)

              # Read fixed part of local file header (30 bytes)
              fixed_header = io.read(30)

              # Extract variable lengths from fixed header
              _signature, _version, _flags, _method, _time, _date, _crc32,
              _comp_size, _uncomp_size, filename_length, extra_length = fixed_header.unpack("VvvvvvVVVvv")

              # Read variable parts
              variable_data = io.read(filename_length + extra_length)

              # Parse complete local file header
              LocalFileHeader.from_binary(fixed_header + variable_data)

              # Now we're positioned right after the local file header, read compressed data
              compressed_data = io.read(entry.compressed_size)

              # Decompress data
              decompressed_data = decompress_data(
                compressed_data,
                entry.compression_method,
                entry.uncompressed_size,
              )

              # Verify CRC
              calculated_crc = Omnizip::Checksums::Crc32.new.tap do |c|
                c.update(decompressed_data)
              end.finalize
              if calculated_crc != entry.crc32
                raise Omnizip::ChecksumError,
                      "CRC mismatch for #{entry.filename}"
              end

              # Write decompressed data
              File.binwrite(output_path, decompressed_data)

              # Set file permissions if Unix
              if entry.unix_permissions.positive?
                File.chmod(entry.unix_permissions & 0o777, output_path)
              end
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

        private

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
