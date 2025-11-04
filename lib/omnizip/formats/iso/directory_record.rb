# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # ISO 9660 Directory Record
      # Represents a file or directory entry
      class DirectoryRecord
        attr_reader :length, :extended_attr_length, :location, :data_length,
                    :recording_date, :flags, :file_unit_size, :interleave_gap_size,
                    :volume_sequence_number, :name, :system_use

        # Parse directory record from binary data
        #
        # @param data [String] Binary record data
        # @param offset [Integer] Offset in data to start parsing
        # @return [DirectoryRecord] Parsed record
        def self.parse(data, offset = 0)
          new.tap { |record| record.parse(data, offset) }
        end

        # Parse record data
        #
        # @param data [String] Binary data
        # @param offset [Integer] Starting offset
        def parse(data, offset = 0)
          # Byte 0: Length of directory record
          @length = data.getbyte(offset)
          return if @length.zero? # Padding

          # Byte 1: Extended attribute record length
          @extended_attr_length = data.getbyte(offset + 1)

          # Bytes 2-9: Location of extent (both-endian)
          @location = data[offset + 2, 4].unpack1("V")

          # Bytes 10-17: Data length (both-endian)
          @data_length = data[offset + 10, 4].unpack1("V")

          # Bytes 18-24: Recording date and time
          @recording_date = parse_record_datetime(data[offset + 18, 7])

          # Byte 25: File flags
          @flags = data.getbyte(offset + 25)

          # Byte 26: File unit size (for interleaved files)
          @file_unit_size = data.getbyte(offset + 26)

          # Byte 27: Interleave gap size
          @interleave_gap_size = data.getbyte(offset + 27)

          # Bytes 28-31: Volume sequence number (both-endian)
          @volume_sequence_number = data[offset + 28, 2].unpack1("v")

          # Byte 32: Length of file identifier
          name_length = data.getbyte(offset + 32)

          # Bytes 33+: File identifier
          @name = data[offset + 33, name_length]

          # Parse file identifier
          parse_name

          # System Use field (Rock Ridge extensions, etc.)
          # Located after name and padding
          su_offset = offset + 33 + name_length
          su_offset += 1 if name_length.even? # Padding byte

          return unless su_offset < offset + @length

          @system_use = data[su_offset, offset + @length - su_offset]
        end

        # Check if entry is a directory
        #
        # @return [Boolean] true if directory
        def directory?
          @flags.anybits?(Iso::FLAG_DIRECTORY)
        end

        # Check if entry is hidden
        #
        # @return [Boolean] true if hidden
        def hidden?
          @flags.anybits?(Iso::FLAG_HIDDEN)
        end

        # Check if this is the current directory entry
        #
        # @return [Boolean] true if current directory
        def current_directory?
          @name == "\x00"
        end

        # Check if this is the parent directory entry
        #
        # @return [Boolean] true if parent directory
        def parent_directory?
          @name == "\x01"
        end

        # Get file size
        #
        # @return [Integer] Size in bytes
        def size
          @data_length
        end

        # Get modification time
        #
        # @return [Time, nil] Modification time
        def mtime
          @recording_date
        end

        private

        # Parse directory record datetime (7-byte format)
        #
        # @param data [String] 7-byte datetime
        # @return [Time, nil] Parsed time
        def parse_record_datetime(data)
          return nil if data.nil? || data.bytesize < 7

          year = 1900 + data.getbyte(0)
          month = data.getbyte(1)
          day = data.getbyte(2)
          hour = data.getbyte(3)
          minute = data.getbyte(4)
          second = data.getbyte(5)
          # Timezone offset at byte 6 (15-minute intervals from GMT)

          Time.new(year, month, day, hour, minute, second)
        rescue ArgumentError
          nil
        end

        # Parse file identifier name
        def parse_name
          # Special cases for current and parent directory
          return if @name == "\x00" || @name == "\x01"

          # Remove version number (;1) if present
          @name = @name.split(";").first if @name.include?(";")

          # Convert to UTF-8 and strip
          @name = @name.force_encoding("UTF-8").strip
        end
      end
    end
  end
end
