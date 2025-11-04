# frozen_string_literal: true

require_relative "constants"
require_relative "file_collector"
require_relative "stream_compressor"
require_relative "header_writer"
require_relative "models/file_entry"
require_relative "split_archive_writer"
require_relative "header_encryptor"
require_relative "encrypted_header"
require_relative "../../models/split_options"

module Omnizip
  module Formats
    module SevenZip
      # .7z archive writer
      # Creates .7z archives from files and directories
      class Writer
        include Constants

        attr_reader :output_path, :options, :entries

        # Initialize writer
        #
        # @param output_path [String] Path to output .7z file
        # @param options [Hash] Compression options
        # @option options [Symbol] :algorithm (:lzma2)
        # @option options [Integer] :level (5) 1-9
        # @option options [Boolean] :solid (true)
        # @option options [Array<Symbol>] :filters ([])
        # @option options [Integer] :volume_size Volume size for split archives
        # @option options [String] :password Password for header encryption
        # @option options [Boolean] :encrypt_headers (false) Encrypt headers
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = {
            algorithm: :lzma2,
            level: 5,
            solid: true,
            filters: [],
            encrypt_headers: false
          }.merge(options)
          @collector = FileCollector.new
          @entries = []
        end

        # Add file to archive
        #
        # @param file_path [String] Path to file
        # @param archive_path [String, nil] Path in archive
        def add_file(file_path, archive_path = nil)
          @collector.add_path(file_path, archive_path: archive_path,
                                         recursive: false)
        end

        # Add directory to archive
        #
        # @param dir_path [String] Path to directory
        # @param recursive [Boolean] Add contents recursively
        def add_directory(dir_path, recursive = true)
          @collector.add_path(dir_path, recursive: recursive)
        end

        # Add files matching glob pattern
        #
        # @param pattern [String] Glob pattern
        def add_files(pattern)
          @collector.add_glob(pattern)
        end

        # Write archive
        #
        # @raise [RuntimeError] on write error
        def write
          # Collect files
          @entries = @collector.collect_files

          # Check if split archive requested
          if @options[:volume_size]
            write_split_archive
          else
            # Open output file
            File.open(@output_path, "wb") do |io|
              write_archive(io)
            end
          end
        end

        private

        # Write complete archive
        #
        # @param io [IO] Output stream
        def write_archive(io)
          # Reserve space for start header
          io.write("\0" * START_HEADER_SIZE)

          # Write packed data
          compressed_result = compress_files

          io.write(compressed_result[:data])

          # Build metadata
          next_header_data = build_next_header(compressed_result)

          # Write next header after packed data
          next_header_offset = io.pos - START_HEADER_SIZE
          io.write(next_header_data)

          # Write start header
          header_writer = HeaderWriter.new
          start_header = header_writer.write_start_header(
            next_header_data,
            next_header_offset
          )

          # Rewind and write start header
          io.seek(0)
          io.write(start_header)
        end

        # Compress all files
        #
        # @return [Hash] Compression results
        def compress_files
          compressor = StreamCompressor.new(
            algorithm: @options[:algorithm],
            level: @options[:level],
            filters: @options[:filters]
          )

          # Get files with data
          files_with_data = @entries.select(&:has_stream?)

          if @options[:solid]
            # Solid: compress all files into one stream
            result = compressor.compress_files(files_with_data)
            files_with_data.each_with_index do |entry, i|
              entry.crc = result[:crcs][i]
            end

            {
              data: result[:packed_data],
              folders: [{
                method_id: compressor.method_id,
                properties: compressor.properties,
                unpack_size: result[:unpack_size]
              }],
              pack_sizes: [result[:packed_size]],
              unpack_sizes: result[:unpack_sizes],
              digests: result[:crcs]
            }
          else
            # Non-solid: compress each file separately
            packed_data = String.new(encoding: "BINARY")
            folders = []
            pack_sizes = []
            unpack_sizes = []
            digests = []

            files_with_data.each do |entry|
              data = File.binread(entry.source_path)
              compressed = compressor.compress(data)

              packed_data << compressed
              pack_sizes << compressed.bytesize
              unpack_sizes << data.bytesize

              # Calculate CRC
              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              entry.crc = crc.value
              digests << crc.value

              folders << {
                method_id: compressor.method_id,
                properties: compressor.properties,
                unpack_size: data.bytesize
              }
            end

            {
              data: packed_data,
              folders: folders,
              pack_sizes: pack_sizes,
              unpack_sizes: unpack_sizes,
              digests: digests
            }
          end
        end

        # Build next header metadata
        #
        # @param compressed_result [Hash] Compression results
        # @return [String] Encoded next header
        def build_next_header(compressed_result)
          header_writer = HeaderWriter.new

          header_options = {
            streams: {
              pack_pos: 0,
              pack_sizes: compressed_result[:pack_sizes],
              pack_crcs: [],
              folders: compressed_result[:folders],
              digests: compressed_result[:digests]
            },
            entries: @entries
          }

          next_header = header_writer.write_next_header(header_options)

          # Encrypt headers if requested
          if @options[:encrypt_headers]
            next_header = encrypt_header(next_header)
          end

          next_header
        end

        # Encrypt header data
        #
        # @param header_data [String] Unencrypted header
        # @return [String] Encrypted header with metadata
        def encrypt_header(header_data)
          unless @options[:password]
            raise "Password required for header encryption"
          end

          encryptor = HeaderEncryptor.new(@options[:password])
          result = encryptor.encrypt(header_data)

          # Create encrypted header structure
          encrypted_header = EncryptedHeader.new(
            encrypted_data: result[:data],
            salt: result[:salt],
            iv: result[:iv],
            original_size: result[:size]
          )

          encrypted_header.to_binary
        end

        # Write split archive
        def write_split_archive
          split_options = Omnizip::Models::SplitOptions.new
          split_options.volume_size = @options[:volume_size]

          writer = SplitArchiveWriter.new(@output_path, @options, split_options)

          # Add all collected files
          @entries = @collector.collect_files
          @entries.each do |entry|
            if entry.directory?
              # Directories are already in entries
              next
            elsif entry.source_path
              writer.add_file(entry.source_path, entry.name)
            end
          end

          writer.write
          @entries = writer.entries
        end
      end
    end
  end
end
