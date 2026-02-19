# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "parser"
require_relative "models/stream_info"
require_relative "models/file_entry"
require_relative "stream_decompressor"
require_relative "split_archive_reader"
require_relative "header_encryptor"
require_relative "encrypted_header"
require "fileutils"

module Omnizip
  module Formats
    module SevenZip
      # .7z archive reader
      # Provides read-only access to .7z archives
      class Reader
        include Constants

        attr_reader :file_path, :header, :entries, :stream_info, :split_reader

        # Initialize reader with file path
        #
        # @param file_path [String] Path to .7z file
        # @param options [Hash] Reader options
        # @option options [String] :password Password for encrypted headers
        def initialize(file_path, options = {})
          @file_path = file_path
          @entries = []
          @stream_info = nil
          @split_reader = nil
          @password = options[:password]
        end

        # Open and parse .7z archive
        #
        # @raise [RuntimeError] if file cannot be opened or parsed
        def open
          # Check if this is a split archive
          if split_archive?
            @split_reader = SplitArchiveReader.new(@file_path)
            @split_reader.open
            @header = @split_reader.header
            @entries = @split_reader.entries
            @stream_info = @split_reader.stream_info
          else
            File.open(@file_path, "rb") do |io|
              parse_archive(io)
            end
          end
          self
        end

        # Check if archive is split
        #
        # @return [Boolean] true if split across multiple volumes
        def split?
          @split_reader&.split? || false
        end

        # Get total number of volumes (for split archives)
        #
        # @return [Integer] Number of volumes
        def total_volumes
          @split_reader&.total_volumes || 1
        end

        # Get volume size (for split archives)
        #
        # @return [Integer] Volume size in bytes
        def volume_size
          @split_reader&.volume_size || File.size(@file_path)
        end

        # Get list of volumes (for split archives)
        #
        # @return [Array<String>] Volume paths
        def volumes
          @split_reader&.volumes || [@file_path]
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
          # Delegate to split reader if available
          if @split_reader
            @split_reader.extract_entry(entry_name, output_path)
            return
          end

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

        # Check if headers are encrypted
        #
        # @return [Boolean] true if headers are encrypted
        def encrypted?
          !@encrypted_header.nil?
        end

        # Check if can decrypt headers (password provided)
        #
        # @return [Boolean] true if password available for encrypted headers
        def can_decrypt?
          encrypted? && !@password.nil?
        end

        private

        # Parse .7z archive structure
        #
        # @param io [io] Input stream
        def parse_archive(io)
          # Read and validate start header
          @header = Header.read(io)

          # Read next header metadata
          # NOTE: next_header_offset is from the END of the Start Header (byte 32)
          # NOT from the end of the file
          next_header_pos = Constants::START_HEADER_SIZE + @header.next_header_offset
          io.seek(next_header_pos)
          next_header_data = io.read(@header.next_header_size)

          # Check if header is encoded (compressed or encrypted)
          # ENCODED_HEADER (0x17) can mean compressed or encrypted
          first_byte = next_header_data.getbyte(0)
          if first_byte == PropertyId::ENCODED_HEADER
            # Try to parse as encrypted first (if enough data and has structure)
            if next_header_data.bytesize >= 54
              begin
                # Check if it's actually an encrypted header
                EncryptedHeader.from_binary(next_header_data)
                # If we got here, it's encrypted - try to decrypt
                next_header_data = decrypt_header(next_header_data)
              rescue RuntimeError => e
                # Re-raise password-related errors
                if e.message.include?("Password required") || e.message.include?("incorrect password")
                  raise
                end

                # Not encrypted - it's a compressed header
                # Decompress it using the encoded stream info
                next_header_data = decompress_encoded_header(io,
                                                             next_header_data)
              rescue StandardError
                # Parsing error - not an encrypted header, try decompression
                next_header_data = decompress_encoded_header(io,
                                                             next_header_data)
              end
            else
              # Too short for encrypted header, must be compressed
              next_header_data = decompress_encoded_header(io, next_header_data)
            end
          end

          # Parse metadata
          parser = Parser.new(next_header_data)
          @stream_info, @entries = parse_metadata(parser)

          # Map entries to their folders/streams
          map_entries_to_streams
        end

        # Decrypt encrypted header
        #
        # @param encrypted_data [String] Encrypted header bytes
        # @return [String] Decrypted header data
        # @raise [RuntimeError] if password not provided
        def decrypt_header(encrypted_data)
          # Parse encrypted header structure
          @encrypted_header = EncryptedHeader.from_binary(encrypted_data)

          unless @password
            raise "Archive headers are encrypted. Password required to access."
          end

          # Decrypt using password
          encryptor = HeaderEncryptor.new(@password)
          encryptor.decrypt(
            @encrypted_header.encrypted_data,
            @encrypted_header.salt,
            @encrypted_header.iv,
          )
        rescue OpenSSL::Cipher::CipherError => e
          raise "Failed to decrypt headers: incorrect password (#{e.message})"
        end

        # Decompress encoded (compressed) header
        #
        # @param io [IO] Archive file handle
        # @param encoded_data [String] Encoded header bytes
        # @return [String] Decompressed header data
        def decompress_encoded_header(io, encoded_data)
          # Skip ENCODED_HEADER marker
          parser = Parser.new(encoded_data[1..])

          # Parse the streams info for the encoded header
          stream_info = Models::StreamInfo.new

          # Read streams info - can be either MAIN_STREAMS_INFO or direct stream properties
          type = parser.read_byte

          if type == PropertyId::MAIN_STREAMS_INFO
            parse_streams_info(parser, stream_info)
          elsif type == PropertyId::PACK_INFO
            # Direct PackInfo without MAIN_STREAMS_INFO wrapper
            parser.read_pack_info(stream_info)

            # Read UNPACK_INFO
            type = parser.read_byte
            if type == PropertyId::UNPACK_INFO
              parser.read_unpack_info(stream_info)
            end
          else
            raise "Unexpected property in encoded header: 0x#{type.to_s(16)}"
          end

          # Decompress the header using the stream info
          pack_pos = @header.start_pos_after_header + stream_info.pack_pos
          folder = stream_info.folders[0]
          pack_size = stream_info.pack_sizes[0]
          unpack_size = folder.uncompressed_size

          decompressor = StreamDecompressor.new(io, folder, pack_pos, pack_size)
          decompressor.decompress(unpack_size)
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
          until parser.eof?
            prop_type = parser.read_byte

            case prop_type
            when PropertyId::MAIN_STREAMS_INFO
              parse_streams_info(parser, stream_info)
            when PropertyId::FILES_INFO
              entries = parser.read_files_info
            when PropertyId::K_END
              break
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
          until parser.eof?
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
            else
              # Unknown property within streams_info - skip it
              parser.skip_data if !parser.eof? && parser.peek_byte != PropertyId::K_END
            end
          end

          # Consume final K_END for MAIN_STREAMS_INFO section
          parser.read_byte if !parser.eof? && parser.peek_byte == PropertyId::K_END
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
            entry.size = @stream_info.unpack_sizes[stream_idx] if @stream_info.unpack_sizes[stream_idx]
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

          # For solid archives, multiple files share one compressed stream
          # We need to decompress the entire folder and extract the correct portion
          num_files_in_folder = @stream_info.num_unpack_streams_in_folders[entry.folder_index] || 1

          if num_files_in_folder > 1
            # Solid archive: decompress entire folder and extract this file's portion
            total_unpack_size = folder.uncompressed_size
            decompressor = StreamDecompressor.new(io, folder, pack_pos,
                                                  pack_size)
            full_data = decompressor.decompress(total_unpack_size)

            # Find offset of this file within the uncompressed stream
            file_offset = 0
            @entries.each do |e|
              break if e.file_index == entry.file_index

              file_offset += e.size if e.has_stream? && e.folder_index == entry.folder_index
            end

            # Extract this file's data
            data = full_data[file_offset, entry.size]

            # Verify CRC if available
            if entry.crc
              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              unless crc.value == entry.crc
                raise "CRC mismatch for #{entry.name}: expected 0x#{entry.crc.to_s(16)}, got 0x#{crc.value.to_s(16)}"
              end
            end

            data
          else
            # Non-solid: each file has its own compressed stream
            decompressor = StreamDecompressor.new(io, folder, pack_pos,
                                                  pack_size)
            expected_crc = entry.crc
            decompressor.decompress_and_verify(entry.size, expected_crc)
          end
        rescue StandardError => e
          warn "Extraction failed for #{entry.name}: #{e.message}"
          raise
        end

        # Check if file path indicates a split archive
        #
        # @return [Boolean] true if appears to be split
        def split_archive?
          # Numeric pattern: .001, .002, etc.
          return true if /\.\d{3}$/.match?(@file_path)

          # Alpha pattern: .7z.aa, .tar.ab, etc. (but not .7z, .tar, .zip alone)
          # Must have a known archive extension followed by alpha suffix
          return true if /\.(7z|tar|zip|rar)\.[a-z]{2,}$/.match?(@file_path)

          false
        end
      end
    end
  end
end
