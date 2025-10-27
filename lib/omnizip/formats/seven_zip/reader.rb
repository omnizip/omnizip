# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "parser"
require_relative "models/stream_info"
require_relative "models/file_entry"
require_relative "stream_decompressor"
require "fileutils"

module Omnizip
  module Formats
    module SevenZip
      # .7z archive reader
      # Provides read-only access to .7z archives
      class Reader
        include Constants

        attr_reader :file_path, :header, :entries, :stream_info

        # Initialize reader with file path
        #
        # @param file_path [String] Path to .7z file
        def initialize(file_path)
          @file_path = file_path
          @entries = []
          @stream_info = nil
        end

        # Open and parse .7z archive
        #
        # @raise [RuntimeError] if file cannot be opened or parsed
        def open
          File.open(@file_path, "rb") do |io|
            parse_archive(io)
          end
          self
        end

        # List all files in archive
        #
        # @return [Array<Models::FileEntry>] File entries
        def list_files
          @entries
        end

        # Extract file to output path
        #
        # @param entry_name [String] File name to extract
        # @param output_path [String] Destination path
        # @raise [RuntimeError] if entry not found or extraction fails
        def extract_entry(entry_name, output_path)
          entry = @entries.find { |e| e.name == entry_name }
          raise "Entry not found: #{entry_name}" unless entry

          # Create directory if needed
          FileUtils.mkdir_p(File.dirname(output_path))

          # Extract file
          if entry.directory?
            FileUtils.mkdir_p(output_path)
          elsif entry.has_stream?
            File.open(@file_path, "rb") do |io|
              data = extract_entry_data(io, entry)
              File.binwrite(output_path, data)
            end

            # Set timestamp if available
            if entry.mtime
              File.utime(entry.atime || entry.mtime || Time.now,
                         entry.mtime || Time.now,
                         output_path)
            end
          else
            # Empty file
            FileUtils.touch(output_path)
          end
        end

        # Extract all files to directory
        #
        # @param output_dir [String] Destination directory
        # @raise [RuntimeError] on extraction error
        def extract_all(output_dir)
          FileUtils.mkdir_p(output_dir)

          @entries.each do |entry|
            output_path = File.join(output_dir, entry.name)
            extract_entry(entry.name, output_path)
          end
        end

        # Check if archive is valid .7z format
        #
        # @return [Boolean] true if valid
        def valid?
          !@header.nil? && @header.valid?
        end

        private

        # Parse .7z archive structure
        #
        # @param io [IO] Input stream
        def parse_archive(io)
          # Read and validate start header
          @header = Header.read(io)

          # Read next header metadata
          io.seek(@header.start_pos_after_header +
                  @header.next_header_offset)
          next_header_data = io.read(@header.next_header_size)

          # Parse metadata
          parser = Parser.new(next_header_data)
          @stream_info, @entries = parse_metadata(parser)

          # Map entries to their folders/streams
          map_entries_to_streams
        end

        # Parse archive metadata
        #
        # @param parser [Parser] Parser instance
        # @return [Array<StreamInfo, Array<Models::FileEntry>>] Parsed data
        def parse_metadata(parser)
          stream_info = Models::StreamInfo.new
          entries = []

          # Read main header
          type = parser.read_byte
          raise "Expected Header, got 0x#{type.to_s(16)}" unless
            type == PropertyId::HEADER

          # Parse header sections
          until parser.eof? || parser.peek_byte == PropertyId::K_END
            prop_type = parser.read_byte

            case prop_type
            when PropertyId::MAIN_STREAMS_INFO
              parse_streams_info(parser, stream_info)
            when PropertyId::FILES_INFO
              entries = parser.read_files_info
            else
              # Skip unknown properties
              parser.skip_data if !parser.eof? &&
                                  parser.peek_byte != PropertyId::K_END
            end
          end

          parser.read_byte if !parser.eof? &&
                              parser.peek_byte == PropertyId::K_END

          [stream_info, entries]
        end

        # Parse streams info section
        #
        # @param parser [Parser] Parser instance
        # @param stream_info [Models::StreamInfo] Stream info to populate
        def parse_streams_info(parser, stream_info)
          until parser.eof? || parser.peek_byte == PropertyId::K_END
            prop_type = parser.read_byte

            case prop_type
            when PropertyId::PACK_INFO
              parser.read_pack_info(stream_info)
            when PropertyId::UNPACK_INFO
              parser.read_unpack_info(stream_info)
            when PropertyId::SUBSTREAMS_INFO
              parser.read_substreams_info(stream_info)
            when PropertyId::K_END
              break
            end
          end

          parser.read_byte if !parser.eof? &&
                              parser.peek_byte == PropertyId::K_END
        end

        # Map entries to their folders and streams
        def map_entries_to_streams
          return if @stream_info.nil?

          stream_idx = 0
          @entries.each_with_index do |entry, i|
            next unless entry.has_stream?

            # Find which folder this stream belongs to
            folder_idx = 0
            accumulated = 0
            @stream_info.num_unpack_streams_in_folders.each_with_index do |num, fi|
              if stream_idx < accumulated + num
                folder_idx = fi
                break
              end
              accumulated += num
            end

            entry.folder_index = folder_idx
            entry.file_index = i
            stream_idx += 1
          end
        end

        # Extract entry data
        #
        # @param io [IO] Archive file handle
        # @param entry [Models::FileEntry] Entry to extract
        # @return [String] Extracted data
        def extract_entry_data(io, entry)
          return "" unless entry.has_stream?
          return "" unless @stream_info

          folder = @stream_info.folders[entry.folder_index]
          return "" unless folder

          # Calculate pack position
          pack_pos = @header.start_pos_after_header +
                     @stream_info.pack_pos

          # Get pack size for this folder
          pack_idx = 0
          entry.folder_index.times do |i|
            num_streams = @stream_info.folders[i].pack_stream_indices.size
            pack_idx += num_streams
          end
          pack_size = @stream_info.pack_sizes[pack_idx] || 0

          # Decompress
          decompressor = StreamDecompressor.new(io, folder,
                                                pack_pos, pack_size)
          expected_crc = entry.crc
          decompressor.decompress_and_verify(entry.size, expected_crc)
        rescue StandardError => e
          warn "Extraction failed for #{entry.name}: #{e.message}"
          raise
        end
      end
    end
  end
end
