# frozen_string_literal: true

require_relative "constants"
require_relative "models/folder"
require_relative "models/coder_info"
require_relative "models/stream_info"
require_relative "models/file_entry"

module Omnizip
  module Formats
    module SevenZip
      # Binary data parser for .7z format
      # Implements variable-length encoding and bit vector handling
      class Parser
        include Constants

        attr_reader :data, :position

        # Initialize parser with binary data
        #
        # @param data [String] Binary data to parse
        def initialize(data)
          @data = data.b
          @position = 0
        end

        # Read a single byte
        #
        # @return [Integer] Byte value (0-255)
        # @raise [EOFError] if no more data available
        def read_byte
          raise EOFError, "End of data" if @position >= @data.bytesize

          byte = @data.getbyte(@position)
          @position += 1
          byte
        end

        # Read variable-length number (7-Zip specific encoding)
        # First byte indicates how many additional bytes to read
        #
        # @return [Integer] Decoded number
        def read_number
          first_byte = read_byte

          # Single byte number (0-127)
          return first_byte if first_byte.nobits?(0x80)

          # Multi-byte number
          value = read_byte

          # Two-byte number
          return ((first_byte & 0x3F) << 8) | value if first_byte.nobits?(0x40)

          # Multi-byte number (3-8 bytes)
          value |= read_byte << 8
          mask = 0x20
          (2...8).each do |i|
            return value | ((first_byte & (mask - 1)) << (8 * i)) if
              first_byte.nobits?(mask)

            value |= read_byte << (8 * i)
            mask >>= 1
          end

          value
        end

        # Read 32-bit variable-length number
        #
        # @return [Integer] Number value (max 32-bit)
        # @raise [RuntimeError] if value exceeds 32-bit range
        def read_number32
          first_byte = peek_byte
          if first_byte.nobits?(0x80)
            @position += 1
            return first_byte
          end

          value = read_number
          raise "Unsupported 32-bit value" if value >= 0x80000000

          value
        end

        # Read property ID
        #
        # @return [Integer] Property ID
        def read_id
          read_number
        end

        # Read fixed-size unsigned 32-bit integer (little-endian)
        #
        # @return [Integer] 32-bit value
        def read_uint32
          raise EOFError if @position + 4 > @data.bytesize

          value = @data[@position, 4].unpack1("V")
          @position += 4
          value
        end

        # Read fixed-size unsigned 64-bit integer (little-endian)
        #
        # @return [Integer] 64-bit value
        def read_uint64
          raise EOFError if @position + 8 > @data.bytesize

          value = @data[@position, 8].unpack1("Q<")
          @position += 8
          value
        end

        # Read bit vector
        # Format: 1 byte flag, then either all 1s or bit array
        #
        # @param num_items [Integer] Number of items in bit vector
        # @return [Array<Boolean>] Bit vector
        def read_bit_vector(num_items)
          all_defined = read_byte
          num_bytes = (num_items + 7) / 8

          if all_defined.zero?
            # Explicit bit vector
            raise EOFError if @position + num_bytes > @data.bytesize

            bits_data = @data[@position, num_bytes]
            @position += num_bytes
            decode_bit_vector(bits_data, num_items)
          else
            # All bits are set
            Array.new(num_items, true)
          end
        end

        # Read raw bytes
        #
        # @param count [Integer] Number of bytes to read
        # @return [String] Binary string
        def read_bytes(count)
          raise EOFError if @position + count > @data.bytesize

          bytes = @data[@position, count]
          @position += count
          bytes
        end

        # Skip bytes
        #
        # @param count [Integer] Number of bytes to skip
        def skip(count)
          @position += count
        end

        # Peek at next byte without advancing position
        #
        # @return [Integer] Next byte value
        def peek_byte
          raise EOFError if @position >= @data.bytesize

          @data.getbyte(@position)
        end

        # Check if at end of data
        #
        # @return [Boolean] true if no more data
        def eof?
          @position >= @data.bytesize
        end

        # Get remaining byte count
        #
        # @return [Integer] Bytes remaining
        def remaining
          @data.bytesize - @position
        end

        # Read pack info section
        # Contains information about packed streams
        #
        # @param stream_info [StreamInfo] Stream info to populate
        def read_pack_info(stream_info)
          # Read pack position
          stream_info.pack_pos = read_number

          # Read number of pack streams
          num_pack_streams = read_number

          # Read pack sizes
          expect_property(PropertyId::SIZE)
          num_pack_streams.times do
            stream_info.pack_sizes << read_number
          end

          # Optional: read CRCs
          if !eof? && peek_byte == PropertyId::CRC
            read_byte
            defined_vec = read_bit_vector(num_pack_streams)
            num_pack_streams.times do |i|
              stream_info.pack_crcs << (defined_vec[i] ? read_uint32 : nil)
            end
          end

          expect_property(PropertyId::K_END)
        end

        # Read folders section
        # Contains compression method and coder information
        #
        # @param stream_info [StreamInfo] Stream info to populate
        def read_folders(stream_info)
          num_folders = read_number

          # Read each folder
          num_folders.times do
            folder = Models::Folder.new
            read_folder(folder)
            stream_info.folders << folder
          end
        end

        # Read single folder definition
        #
        # @param folder [Models::Folder] Folder to populate
        def read_folder(folder)
          num_coders = read_number
          raise "Too many coders" if num_coders > Constants::MAX_NUM_CODERS

          num_in_streams = 0
          num_out_streams = 0

          # Read coders
          num_coders.times do
            coder = Models::CoderInfo.new
            read_coder(coder)
            folder.coders << coder
            num_in_streams += coder.num_in_streams
            num_out_streams += coder.num_out_streams
          end

          # Read bind pairs
          num_bind_pairs = num_out_streams - 1
          num_bind_pairs.times do
            in_index = read_number
            out_index = read_number
            folder.bind_pairs << [in_index, out_index]
          end

          # Read pack stream indices
          num_pack_streams = num_in_streams - num_bind_pairs
          if num_pack_streams == 1
            # Single pack stream - find unused input
            (0...num_in_streams).each do |i|
              used = folder.bind_pairs.any? { |pair| pair[0] == i }
              unless used
                folder.pack_stream_indices << i
                break
              end
            end
          else
            # Multiple pack streams - read indices
            num_pack_streams.times do
              folder.pack_stream_indices << read_number
            end
          end
        end

        # Read coder definition
        #
        # @param coder [Models::CoderInfo] Coder to populate
        def read_coder(coder)
          main_byte = read_byte

          # Extract coder flags
          id_size = main_byte & 0x0F
          has_attributes = main_byte.anybits?(0x20)
          complex_streams = main_byte.anybits?(0x10)

          # Read method ID
          method_id = 0
          id_size.times do
            method_id = (method_id << 8) | read_byte
          end
          coder.method_id = method_id

          # Read stream counts if complex
          if complex_streams
            coder.num_in_streams = read_number
            coder.num_out_streams = read_number
          else
            coder.num_in_streams = 1
            coder.num_out_streams = 1
          end

          # Read properties if present
          return unless has_attributes

          props_size = read_number
          coder.properties = read_bytes(props_size)
        end

        # Read unpack info section
        # Contains information about unpacked streams
        #
        # @param stream_info [StreamInfo] Stream info to populate
        def read_unpack_info(stream_info)
          # Read folders - FOLDER property is explicit
          expect_property(PropertyId::FOLDER)
          read_folders(stream_info)
          # No END marker after folders - go straight to next property

          # Read unpack sizes
          expect_property(PropertyId::CODERS_UNPACK_SIZE)
          stream_info.folders.each do |folder|
            folder.coders.each do
              folder.unpack_sizes << read_number
            end
          end

          # Optional: read CRCs
          if !(eof? || peek_byte == PropertyId::K_END) && (peek_byte == PropertyId::CRC)
            read_byte
            defined_vec = read_bit_vector(stream_info.num_folders)
            stream_info.num_folders.times do |i|
              stream_info.folders[i].unpack_crc = read_uint32 if defined_vec[i]
            end
          end

          expect_property(PropertyId::K_END)
        end

        # Read substreams info section
        # Maps files to compressed streams
        #
        # @param stream_info [StreamInfo] Stream info to populate
        def read_substreams_info(stream_info)
          # Read number of unpack streams per folder
          if !eof? && peek_byte == PropertyId::NUM_UNPACK_STREAM
            read_byte
            stream_info.folders.each do
              stream_info.num_unpack_streams_in_folders << read_number
            end
          else
            # Default: one stream per folder
            stream_info.folders.size.times do
              stream_info.num_unpack_streams_in_folders << 1
            end
          end

          # Read unpack sizes
          if !eof? && peek_byte == PropertyId::SIZE
            read_byte
            stream_info.folders.each_with_index do |folder, i|
              num_streams = stream_info.num_unpack_streams_in_folders[i]
              if num_streams > 1
                (num_streams - 1).times do
                  stream_info.unpack_sizes << read_number
                end
              end
              # Last stream size = folder unpack size - sum of others
              sum = stream_info.unpack_sizes[(-num_streams + 1)..]&.sum || 0
              stream_info.unpack_sizes << (folder.unpack_sizes.sum - sum)
            end
          end

          # Read digests (CRCs)
          num_digests = stream_info.num_unpack_streams_in_folders.sum
          if !(eof? || peek_byte == PropertyId::K_END) && (peek_byte == PropertyId::CRC)
            read_byte
            defined_vec = read_bit_vector(num_digests)
            num_digests.times do |i|
              stream_info.digests << (defined_vec[i] ? read_uint32 : nil)
            end
          end

          expect_property(PropertyId::K_END) unless eof?
        end

        # Read files info section
        # Contains file metadata (names, timestamps, attributes)
        #
        # @return [Array<Models::FileEntry>] Array of file entries
        def read_files_info
          num_files = read_number
          entries = Array.new(num_files) { Models::FileEntry.new }

          # Read file properties
          until eof? || peek_byte == PropertyId::K_END
            prop_type = read_byte

            case prop_type
            when PropertyId::NAME
              read_names(entries)
            when PropertyId::EMPTY_STREAM
              read_empty_stream(entries)
            when PropertyId::EMPTY_FILE
              read_empty_file(entries)
            when PropertyId::ANTI
              read_anti(entries)
            when PropertyId::CTIME
              read_timestamps(entries, :ctime)
            when PropertyId::ATIME
              read_timestamps(entries, :atime)
            when PropertyId::MTIME
              read_timestamps(entries, :mtime)
            when PropertyId::WIN_ATTRIB
              read_attributes(entries)
            when PropertyId::DUMMY
              skip_data
            else
              skip_data
            end
          end

          read_byte if !eof? && peek_byte == PropertyId::K_END

          entries
        end

        # Read file names
        #
        # @param entries [Array<Models::FileEntry>] File entries
        def read_names(entries)
          # Size of all names in bytes
          size = read_number
          start_pos = @position
          external = read_byte

          if external.zero?
            # Names stored inline
            entries.each do |entry|
              name = String.new
              loop do
                ch1 = read_byte
                ch2 = read_byte
                char_code = ch1 | (ch2 << 8)
                break if char_code.zero?

                name << [char_code].pack("U")
              end
              entry.name = name
            end
          end

          # Ensure we consumed expected bytes
          consumed = @position - start_pos
          skip(size - consumed) if consumed < size
        end

        # Read empty stream flags
        #
        # @param entries [Array<Models::FileEntry>] File entries
        def read_empty_stream(entries)
          skip_size
          empty_stream = read_bit_vector(entries.size)
          entries.each_with_index do |entry, i|
            entry.has_stream = !empty_stream[i]
            entry.is_dir = empty_stream[i]
          end
        end

        # Read empty file flags
        #
        # @param entries [Array<Models::FileEntry>] File entries
        def read_empty_file(entries)
          skip_size
          empty_files = entries.reject(&:has_stream)
          empty_bits = read_bit_vector(empty_files.size)
          empty_files.each_with_index do |entry, i|
            entry.is_empty = !empty_bits[i]
          end
        end

        # Read anti flags
        #
        # @param entries [Array<Models::FileEntry>] File entries
        def read_anti(entries)
          skip_size
          anti_files = entries.select { |e| !e.has_stream && !e.is_empty }
          anti_bits = read_bit_vector(anti_files.size)
          anti_files.each_with_index do |entry, i|
            entry.is_anti = anti_bits[i]
          end
        end

        # Read timestamps
        #
        # @param entries [Array<Models::FileEntry>] File entries
        # @param attr [Symbol] Attribute name (:mtime, :atime, :ctime)
        def read_timestamps(entries, attr)
          skip_size
          defined_bits = read_bit_vector(entries.size)
          external = read_byte

          return unless external.zero?

          entries.each_with_index do |entry, i|
            next unless defined_bits[i]

            time_val = read_uint64
            # Convert Windows FILETIME to Ruby Time
            # (100-nanosecond intervals since 1601-01-01)
            entry.send(:"#{attr}=", windows_time_to_unix(time_val))
          end
        end

        # Read file attributes
        #
        # @param entries [Array<Models::FileEntry>] File entries
        def read_attributes(entries)
          skip_size
          defined_bits = read_bit_vector(entries.size)
          external = read_byte

          return unless external.zero?

          entries.each_with_index do |entry, i|
            entry.attributes = read_uint32 if defined_bits[i]
          end
        end

        # Expect specific property ID
        #
        # @param expected [Integer] Expected property ID
        # @raise [RuntimeError] if property doesn't match
        def expect_property(expected)
          actual = read_byte
          return if actual == expected

          raise "Expected property 0x#{expected.to_s(16)}, " \
                "got 0x#{actual.to_s(16)}"
        end

        # Skip size field
        def skip_size
          read_number
        end

        # Skip property data
        def skip_data
          size = read_number
          skip(size)
        end

        # Convert Windows FILETIME to Unix timestamp
        #
        # @param windows_time [Integer] Windows FILETIME
        # @return [Time] Ruby Time object
        def windows_time_to_unix(windows_time)
          # Windows FILETIME epoch: 1601-01-01
          # Unix epoch: 1970-01-01
          # Difference: 11644473600 seconds
          unix_time = (windows_time / 10_000_000) - 11_644_473_600
          Time.at(unix_time)
        rescue StandardError
          nil
        end

        private

        # Decode bit vector from packed bytes
        #
        # @param bits_data [String] Packed bit data
        # @param num_items [Integer] Number of items
        # @return [Array<Boolean>] Decoded bits
        def decode_bit_vector(bits_data, num_items)
          result = []
          byte_idx = 0
          bit_idx = 7

          num_items.times do
            byte = bits_data.getbyte(byte_idx)
            result << ((byte >> bit_idx) & 1)

            bit_idx -= 1
            if bit_idx.negative?
              bit_idx = 7
              byte_idx += 1
            end
          end

          result
        end
      end
    end
  end
end
