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
require_relative "../../algorithms/lzma2"
require "stringio"

module Omnizip
  module Formats
    module SevenZip
      # .7z archive writer - 7-Zip compatible implementation
      #
      # Creates archives that are fully compatible with official 7-Zip (7zz command).
      #
      # Archive structure:
      # - Start Header (32 bytes)
      # - LZMA2 compressed file data
      # - UNCOMPRESSED Next Header metadata (properties: kHeader, kPackInfo, etc.)
      # - Metadata footer (filename, attributes, timestamps)
      class Writer
        include Constants

        # Constants for array literals used in loops (RuboCop Performance/CollectionLiteralInLoop)
        COPY_MAIN_BYTE = [0x01].pack("C").freeze
        COPY_METHOD_ID = [0x00].pack("C").freeze
        NULL_TERMINATOR = [0x00, 0x00].pack("CC").freeze
        FILE_ATTRIBUTE_ARCHIVE = [0x20].pack("V").freeze

        attr_reader :output_path, :options, :entries

        def initialize(output_path, options = {})
          @output_path = output_path
          @options = {
            algorithm: :lzma2,
            level: 5,
            dict_size: 8 * 1024 * 1024, # 8MB default dictionary
            solid: true, # Solid mode for LZMA2 compression
            filters: [],
            encrypt_headers: false,
          }.merge(options)
          @collector = FileCollector.new
          @entries = []
        end

        def add_file(file_path, archive_path = nil)
          @collector.add_path(file_path, archive_path: archive_path,
                                         recursive: false)
        end

        def add_directory(dir_path, recursive = true)
          @collector.add_path(dir_path, recursive: recursive)
        end

        def add_files(pattern)
          @collector.add_glob(pattern)
        end

        def add_data(archive_path, data, options = {})
          data_str = data.is_a?(String) ? data : data.read

          entry = Models::FileEntry.new
          entry.name = archive_path
          entry.source_path = nil
          entry.size = data_str.bytesize
          entry.mtime = Time.now
          entry.has_stream = true
          entry.instance_variable_set(:@_data, data_str)
          # Store compression options for later use
          entry.compression_options = options if entry.respond_to?(:compression_options=)
          @entries << entry
        end

        def write
          # Collect any files from the collector (if add_file/add_directory was used)
          collected_entries = @collector.collect_files
          # Merge with entries added via add_data
          @entries.concat(collected_entries)

          # Check if split archive requested
          if @options[:volume_size]
            write_split_archive
          else
            File.open(@output_path, "wb") do |io|
              write_archive(io)
            end
          end
        end

        private

        # Write split archive (delegates to SplitArchiveWriter)
        def write_split_archive
          split_options = Omnizip::Models::SplitOptions.new
          split_options.volume_size = @options[:volume_size]

          writer = SplitArchiveWriter.new(@output_path, @options, split_options)

          # Add all collected files
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

        def write_archive(io)
          # Reserve space for start header
          io.write("\0" * START_HEADER_SIZE)

          # Step 1: Collect file data
          file_data = collect_file_data

          # Step 2: Build compressed data based on mode
          if @options[:solid]
            # Solid mode: compress all data together with LZMA2
            packed_data, packed_sizes = build_solid_packed_data(file_data)
          else
            # Non-solid mode: each file stored separately (COPY method - no compression)
            packed_data, packed_sizes = build_non_solid_packed_data(file_data)
          end

          # Step 3: Build Next Header properties
          # This includes kHeader, MAIN_STREAMS_INFO, FILES_INFO, etc.
          next_header_data = build_next_header_properties(file_data,
                                                          packed_sizes)

          # Step 4: Write the complete data section
          # Note: CRC is stored in StartHeader, NOT appended to Next Header
          io.write(packed_data)           # Packed file data
          io.write(next_header_data)      # Next Header (CRC is in StartHeader)

          # Step 5: Write Start Header
          # Next Header starts after the packed data
          # The offset is RELATIVE to the END of the StartHeader (byte 32)
          next_header_offset = packed_data.bytesize

          # Next Header size is the size of the Next Header data WITHOUT the CRC32
          # (CRC32 is appended after the header data, not included in size)
          next_header_size = next_header_data.bytesize

          write_start_header(io, next_header_offset, next_header_size,
                             next_header_data)
        end

        # Build packed data for solid mode (LZMA2 compression)
        def build_solid_packed_data(file_data)
          lzma2_chunk, compressed_size = build_lzma2_compressed_chunk(file_data[:data])
          [lzma2_chunk, [compressed_size]]
        end

        # Build packed data for non-solid mode (COPY - no compression)
        def build_non_solid_packed_data(file_data)
          # For non-solid mode, concatenate raw file data without compression
          packed_data = String.new(encoding: "BINARY")
          packed_sizes = []

          file_data[:streams].each do |stream|
            packed_data << stream[:data]
            packed_sizes << stream[:size]
          end

          [packed_data, packed_sizes]
        end

        def collect_file_data
          files_with_data = @entries.select(&:has_stream?)

          if @options[:solid]
            # Solid mode: combine all files into one stream
            combined = String.new(encoding: "BINARY")
            total_size = 0

            files_with_data.each do |entry|
              data = entry.instance_variable_get(:@_data) || File.binread(entry.source_path)
              combined << data
              total_size += data.bytesize

              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              entry.crc = crc.finalize
              entry.size = data.bytesize
            end

            { data: combined, total_size: total_size,
              streams: [{ data: combined, size: total_size }] }
          else
            # Non-solid mode: each file gets its own stream
            streams = []
            total_size = 0

            files_with_data.each do |entry|
              data = entry.instance_variable_get(:@_data) || File.binread(entry.source_path)

              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              entry.crc = crc.finalize
              entry.size = data.bytesize

              streams << { data: data, size: data.bytesize }
              total_size += data.bytesize
            end

            # Combine all data for writing
            combined = streams.map { |s| s[:data] }.join
            { data: combined, total_size: total_size, streams: streams }
          end
        end

        def build_lzma2_compressed_chunk(data)
          return ["", 0] if data.nil? || data.empty?

          # Use actual LZMA2 compression via 7-Zip SDK encoder
          compressed = compress_with_lzma2(data)
          [compressed, compressed.bytesize]
        end

        def build_next_header_properties(file_data, packed_sizes)
          metadata = String.new(encoding: "BINARY")
          unpack_size = file_data[:total_size]
          num_files = @entries.size
          solid = @options[:solid]

          # kHeader property (0x01)
          metadata << [PropertyId::HEADER].pack("C")

          # kMainStreamsInfo property (0x04) - WRAPPER for stream info
          metadata << [PropertyId::MAIN_STREAMS_INFO].pack("C")

          if solid
            # Solid mode: one pack stream, one folder
            # packed_sizes is a single-element array with compressed size
            compressed_size = packed_sizes.first
            build_solid_streams_info(metadata, unpack_size, compressed_size,
                                     num_files)
          else
            # Non-solid mode: one pack stream per file, one folder per file
            build_non_solid_streams_info(metadata, file_data[:streams])
          end

          # kEnd for MainStreamsInfo
          metadata << [PropertyId::K_END].pack("C")

          # FILES_INFO section
          build_files_info(metadata)

          # kEnd for Header (closes the entire Next Header)
          metadata << [PropertyId::K_END].pack("C")

          # Encrypt headers if requested
          if @options[:encrypt_headers]
            metadata = encrypt_header(metadata)
          end

          metadata
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
            original_size: result[:size],
          )

          encrypted_header.to_binary
        end

        def build_solid_streams_info(metadata, unpack_size, compressed_size,
num_files)
          # kPackInfo property (0x06)
          metadata << [PropertyId::PACK_INFO].pack("C")
          metadata << write_number(0)  # Pack position
          metadata << write_number(1)  # Number of pack streams

          # kSize property
          metadata << [PropertyId::SIZE].pack("C")
          metadata << write_number(compressed_size)

          # kEnd for PackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kUnpackInfo property (0x07)
          metadata << [PropertyId::UNPACK_INFO].pack("C")

          # kFolder property (0x0B)
          metadata << [PropertyId::FOLDER].pack("C")
          metadata << write_number(1) # Number of folders

          # External flag (0 = inline, folders follow)
          metadata << [0].pack("C")

          # Folder definitions
          build_folder_coder(metadata)

          # kCodersUnpackSize - comes AFTER all folder definitions
          metadata << [PropertyId::CODERS_UNPACK_SIZE].pack("C")
          metadata << write_number(unpack_size)

          # kEnd for UnpackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kSubStreamsInfo - for solid archives with multiple files
          metadata << [PropertyId::SUBSTREAMS_INFO].pack("C")
          if num_files > 1

            # NUM_UNPACK_STREAM - number of files in this folder
            metadata << [PropertyId::NUM_UNPACK_STREAM].pack("C")
            metadata << write_number(num_files)

            # SIZE - size of each file's data (except the last one)
            # Per 7-Zip spec: only write numSubstreams-1 sizes, last is calculated
            # from folder's unpack size minus sum of written sizes
            metadata << [PropertyId::SIZE].pack("C")
            @entries[0..-2].each do |entry| # All except last
              metadata << write_number(entry.size)
            end

            # CRCs
            metadata << [PropertyId::CRC].pack("C")
            metadata << [1].pack("C") # All defined
            @entries.each do |entry|
              # Use 0 for entries without CRC (empty files)
              crc = entry.crc || 0
              metadata << [crc].pack("V")
            end

          else
            # Single file: CRC goes in SubStreamsInfo
            metadata << [PropertyId::CRC].pack("C")
            metadata << [1].pack("C") # All defined
            # Use 0 for entries without CRC (empty files)
            crc = @entries.first&.crc || 0
            metadata << [crc].pack("V")
          end
          metadata << [PropertyId::K_END].pack("C")
        end

        def build_non_solid_streams_info(metadata, streams)
          num_streams = streams.size

          # kPackInfo property (0x06)
          metadata << [PropertyId::PACK_INFO].pack("C")
          metadata << write_number(0) # Pack position
          metadata << write_number(num_streams) # Number of pack streams

          # kSize property - sizes of each pack stream
          metadata << [PropertyId::SIZE].pack("C")
          streams.each do |stream|
            metadata << write_number(stream[:size])
          end

          # kEnd for PackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kUnpackInfo property (0x07)
          metadata << [PropertyId::UNPACK_INFO].pack("C")

          # kFolder property (0x0B)
          metadata << [PropertyId::FOLDER].pack("C")
          metadata << write_number(num_streams) # Number of folders

          # External flag for all folders
          metadata << [0].pack("C")

          # Folder definitions (coders only, no sizes yet)
          streams.each do |_stream|
            # Number of coders
            metadata << write_number(1)
            # Coder info for COPY
            # MainByte format: bits 0-3 = num bytes for CodecID (0-15), bit 4 = is_complex, bits 5-7 = num props
            # For COPY: 1 byte CodecID (0x00), no properties
            metadata << COPY_MAIN_BYTE  # MainByte: 1 byte for CodecID, no props
            metadata << COPY_METHOD_ID  # Method ID: COPY = 0x00
          end

          # kCodersUnpackSize - comes after ALL folder definitions
          metadata << [PropertyId::CODERS_UNPACK_SIZE].pack("C")
          streams.each do |stream|
            metadata << write_number(stream[:size])
          end

          # kEnd for UnpackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kSubStreamsInfo - CRCs for each file
          metadata << [PropertyId::SUBSTREAMS_INFO].pack("C")
          metadata << [PropertyId::CRC].pack("C")
          metadata << [1].pack("C") # All defined
          @entries.each do |entry|
            # Use 0 for entries without CRC (empty files)
            crc = entry.crc || 0
            metadata << [crc].pack("V")
          end
          metadata << [PropertyId::K_END].pack("C")
        end

        def build_folder_coder(metadata)
          # Number of coders
          metadata << write_number(1)

          # Coder info for LZMA2 (method 0x21)
          # MainByte format:
          #   bits 0-3 = num bytes for CodecID (1 for 0x21)
          #   bit 4 = IsComplexCoder (0)
          #   bits 5-7 = num property bytes (we set to 0 and write size separately)
          # Per 7-Zip SDK, bits 5-7 indicate if there ARE properties (non-zero = has props)
          # MainByte = 0x21 means: 1 byte for CodecID + has properties
          metadata << [0x21].pack("C")  # MainByte: 1 byte for CodecID + has properties
          metadata << [0x21].pack("C")  # Method ID: LZMA2 = 0x21

          # LZMA2 property byte encodes dictionary size
          dict_size = @options[:dict_size] || (8 * 1024 * 1024)
          prop_byte = encode_lzma2_dict_size(dict_size)

          # 7-Zip format: write property SIZE (as VLI), then property bytes
          metadata << write_number(1) # PropsSize = 1 byte
          metadata << [prop_byte].pack("C") # Property byte
        end

        def build_files_info(metadata)
          # kFilesInfo property (0x05)
          metadata << [PropertyId::FILES_INFO].pack("C")

          # Number of files
          metadata << write_number(@entries.size)

          # Build NAME property (0x11)
          # Format: [NAME] [size] [external] [UTF-16LE names with null terminators]
          name_data = String.new(encoding: "BINARY")

          @entries.each do |entry|
            # Encode name as UTF-16LE and force to BINARY
            name_utf16le = entry.name.encode("UTF-16LE").b
            # Add null terminator (2 bytes)
            name_data << name_utf16le
            name_data << NULL_TERMINATOR
          end

          metadata << [PropertyId::NAME].pack("C")
          metadata << write_number(name_data.bytesize + 1) # +1 for External byte
          metadata << [0].pack("C") # External = 0 (inline)
          metadata << name_data

          # Build MTIME property (0x14) - MUST come before WIN_ATTRIB per 7-Zip spec
          # Format: [MTIME] [size] [defined bits] [external] [FILETIME values]
          time_data = String.new(encoding: "BINARY")

          @entries.each do |entry|
            unix_time = entry.mtime.to_i
            windows_time = (unix_time + 11_644_473_600) * 10_000_000
            time_data << [windows_time].pack("Q<")
          end

          metadata << [PropertyId::MTIME].pack("C")
          metadata << write_number(time_data.bytesize + 2) # +2 for all_defined and external bytes
          metadata << [1].pack("C")  # All defined
          metadata << [0].pack("C")  # External = 0 (inline)
          metadata << time_data

          # Build WIN_ATTRIB property (0x15) - comes after MTIME per 7-Zip spec
          # Format: [WIN_ATTRIB] [size] [defined bits] [external] [attributes]
          attr_data = String.new(encoding: "BINARY")
          @entries.each do |_entry|
            attr_data << FILE_ATTRIBUTE_ARCHIVE
          end

          metadata << [PropertyId::WIN_ATTRIB].pack("C")
          metadata << write_number(attr_data.bytesize + 2) # +2 for all_defined and external bytes
          metadata << [1].pack("C")  # All defined
          metadata << [0].pack("C")  # External = 0 (inline)
          metadata << attr_data

          # kEnd for FilesInfo
          metadata << [PropertyId::K_END].pack("C")
        end

        def compress_with_lzma2(data)
          # Use 7-Zip SDK LZMA2 encoder for 7-Zip format
          dict_size = [4096, data.bytesize].max

          encoder = Omnizip::Implementations::SevenZip::LZMA2::Encoder.new(
            dict_size: dict_size,
            lc: 3,
            lp: 0,
            pb: 2,
            standalone: false, # No property byte (raw mode)
          )

          encoder.encode(data)
        end

        # Encode dictionary size to LZMA2 property byte
        #
        # LZMA2 property byte encoding (per XZ spec, same for 7-Zip):
        #   dict_size = (2 | (props & 1)) << (props / 2 + 11)
        #
        # This gives sizes from 4KB (props=0) to 4GB (props=40)
        #
        # @param dict_size [Integer] Dictionary size in bytes
        # @return [Integer] Property byte (0-40)
        def encode_lzma2_dict_size(dict_size)
          # Find the smallest prop value that gives >= dict_size
          (0..40).each do |prop|
            # Decode formula: dict_size = (2 | (prop & 1)) << (prop / 2 + 11)
            base = 2 | (prop & 1)
            size = base << ((prop / 2) + 11)
            return prop if size >= dict_size
          end

          # Maximum property value
          40
        end

        def build_next_header_metadata(compressed_size, unpack_size)
          metadata = String.new(encoding: "BINARY")

          # kHeader property (0x01)
          metadata << [PropertyId::HEADER].pack("C")

          # kMainStreamsInfo property (0x04) - WRAPPER for stream info
          metadata << [PropertyId::MAIN_STREAMS_INFO].pack("C")

          # kPackInfo property (0x06)
          metadata << [PropertyId::PACK_INFO].pack("C")
          metadata << write_number(0)  # Pack position
          metadata << write_number(1)  # Number of pack streams

          # kSize property
          metadata << [PropertyId::SIZE].pack("C")
          metadata << write_number(compressed_size)

          # kEnd for PackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kUnpackInfo property (0x07)
          metadata << [PropertyId::UNPACK_INFO].pack("C")

          # kFolder property (0x0B)
          metadata << [PropertyId::FOLDER].pack("C")
          metadata << write_number(1) # Number of folders

          # Folder content
          metadata << [0].pack("C") # External flag (0 = inline)

          # Number of coders
          metadata << write_number(1)

          # Coder info for LZMA2
          # Method ID: LZMA2 = 0x21
          # Main byte: 1 byte for ID + 0x00 for no properties
          metadata << [1].pack("C") # 1 byte for ID
          metadata << [0x21].pack("C") # LZMA2 method ID

          # kCodersUnpackSize
          metadata << [PropertyId::CODERS_UNPACK_SIZE].pack("C")
          metadata << write_number(unpack_size)

          # kSubStreamsInfo property (0x08)
          metadata << [PropertyId::SUBSTREAMS_INFO].pack("C")

          # kCRC property (0x0a)
          metadata << [PropertyId::CRC].pack("C")
          metadata << [1].pack("C") # All streams have CRC (1 = yes, 0 = no)

          # EMPTY_STREAM (0x0e): Number of empty unpack streams
          metadata << [PropertyId::EMPTY_STREAM].pack("C")
          metadata << [0].pack("C") # 0 empty streams (file has data)

          # kEnd for SubStreamsInfo
          metadata << [PropertyId::K_END].pack("C")

          # kEnd for UnpackInfo
          metadata << [PropertyId::K_END].pack("C")

          # kEnd for MainStreamsInfo
          metadata << [PropertyId::K_END].pack("C")

          # kEnd for Header
          metadata << [PropertyId::K_END].pack("C")

          metadata
        end

        def build_metadata_footer
          footer = String.new(encoding: "BINARY")

          # Single loop to add filename, attributes, and timestamps for each entry
          @entries.each do |entry|
            # Add filename in UTF-16LE with null terminator
            entry.name.encode("UTF-16LE").each_byte do |byte|
              footer << [byte].pack("C")
            end
            footer << NULL_TERMINATOR

            # Add file attributes (Windows FILE attributes)
            footer << FILE_ATTRIBUTE_ARCHIVE

            # Add Windows FILETIME for modification time
            unix_time = entry.mtime.to_i
            windows_time = (unix_time + 11_644_473_600) * 10_000_000
            footer << [windows_time].pack("Q<")
          end

          footer
        end

        def write_start_header(io, next_header_offset, next_header_size,
next_header_data)
          header = String.new(encoding: "BINARY")

          # Signature (6 bytes)
          header << SIGNATURE

          # Version (2 bytes)
          header << [MAJOR_VERSION, MINOR_VERSION].pack("CC")

          # Calculate CRC for next header info
          next_header_info = String.new(encoding: "BINARY")
          next_header_info << [next_header_offset].pack("Q<")
          next_header_info << [next_header_size].pack("Q<")

          # Calculate CRC for next header
          crc = Omnizip::Checksums::Crc32.new
          crc.update(next_header_data)
          next_header_crc = crc.finalize
          next_header_info << [next_header_crc].pack("V")

          # Calculate CRC for next header info
          info_crc = Omnizip::Checksums::Crc32.new
          info_crc.update(next_header_info)

          # Start header CRC (4 bytes)
          header << [info_crc.finalize].pack("V")

          # Next header info (20 bytes)
          header << next_header_info

          # Write at the beginning
          io.seek(0)
          io.write(header)
        end

        # Encode variable-length integer (7-Zip VLI format)
        #
        # 7-Zip VLI encoding uses the first byte's high bits to determine
        # the number of additional bytes:
        #   0xxxxxxx               : value = xxxxxxx (0-127)
        #   10xxxxxx BYTE y[1]     : value = (xxxxxx << 8) + y
        #   110xxxxx BYTE y[2]     : value = (xxxxx << 16) + y
        #   1110xxxx BYTE y[3]     : value = (xxxx << 24) + y
        #   ...up to 8 bytes total
        def write_number(value)
          # Single byte encoding (0-127)
          return [value].pack("C") if value < 0x80

          # Determine number of bytes needed using 7-Zip VLI thresholds
          # 2 bytes: 128 - 16383 (0x80 - 0x3FFF encoded as 10xxxxxx + 1 byte)
          # 3 bytes: 16384 - 2097151 (0x4000 - 0x1FFFFF)
          # etc.
          bytes_needed = case value
                         when 0x80..0x3FFF then 2
                         when 0x4000..0x1F_FFFF then 3
                         when 0x20_0000..0xFFF_FFFF then 4
                         when 0x1000_0000..0x7_FFFF_FFFF then 5
                         when 0x8_0000_0000..0x3FF_FFFF_FFFF then 6
                         when 0x400_0000_0000..0x1_FFFF_FFFF_FFFF then 7
                         else 8
                         end

          result = String.new(encoding: "BINARY")

          case bytes_needed
          when 2
            # 10xxxxxx pattern
            first_byte = 0x80 | (value >> 8)
            result << [first_byte].pack("C")
            result << [value & 0xFF].pack("C")
          when 3
            # 110xxxxx pattern
            first_byte = 0xC0 | (value >> 16)
            result << [first_byte].pack("C")
            result << [(value >> 8) & 0xFF].pack("C")
            result << [value & 0xFF].pack("C")
          when 4
            # 1110xxxx pattern
            first_byte = 0xE0 | (value >> 24)
            result << [first_byte].pack("C")
            result << [(value >> 16) & 0xFF].pack("C")
            result << [(value >> 8) & 0xFF].pack("C")
            result << [value & 0xFF].pack("C")
          when 5
            # 11110xxx pattern
            first_byte = 0xF0 | (value >> 32)
            result << [first_byte].pack("C")
            4.downto(1) do |i|
              result << [(value >> (8 * (i - 1))) & 0xFF].pack("C")
            end
          when 6
            # 111110xx pattern
            first_byte = 0xF8 | (value >> 40)
            result << [first_byte].pack("C")
            5.downto(1) do |i|
              result << [(value >> (8 * (i - 1))) & 0xFF].pack("C")
            end
          when 7
            # 1111110x pattern
            first_byte = 0xFC | (value >> 48)
            result << [first_byte].pack("C")
            6.downto(1) do |i|
              result << [(value >> (8 * (i - 1))) & 0xFF].pack("C")
            end
          else
            # 8 bytes: 11111110 or 11111111 prefix
            result << if value < (1 << 56)
                        [0xFE].pack("C")
                      else
                        [0xFF].pack("C")
                      end
            7.downto(0) { |i| result << [(value >> (8 * i)) & 0xFF].pack("C") }
          end

          result
        end
      end
    end
  end
end
