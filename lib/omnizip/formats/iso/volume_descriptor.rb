# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # ISO 9660 Volume Descriptor
      # Represents the primary volume descriptor containing metadata
      class VolumeDescriptor
        attr_reader :type, :identifier, :version, :volume_identifier,
                    :volume_space_size, :volume_set_size, :volume_sequence_number,
                    :logical_block_size, :path_table_size, :path_table_location,
                    :root_directory_record, :volume_set_identifier,
                    :publisher_identifier, :preparer_identifier,
                    :application_identifier, :creation_date, :modification_date,
                    :system_identifier

        # Standard identifier for ISO 9660
        ISO_IDENTIFIER = "CD001"

        # Parse volume descriptor from binary data
        #
        # @param data [String] Binary sector data (2048 bytes)
        # @return [VolumeDescriptor] Parsed descriptor
        def self.parse(data)
          new.tap { |vd| vd.parse(data) }
        end

        # Parse descriptor data
        #
        # @param data [String] Binary data
        def parse(data)
          raise "Invalid volume descriptor size" unless data.bytesize >= 2048

          # Byte 0: Volume descriptor type
          @type = data.getbyte(0)

          # Bytes 1-5: Standard identifier "CD001"
          @identifier = data[1, 5]
          unless @identifier == ISO_IDENTIFIER
            raise "Invalid ISO identifier: expected #{ISO_IDENTIFIER}, got #{@identifier}"
          end

          # Byte 6: Version (should be 1)
          @version = data.getbyte(6)

          # Parse based on type
          case @type
          when Iso::VD_PRIMARY
            parse_primary_volume_descriptor(data)
          when Iso::VD_TERMINATOR
            # Terminator has no additional data
          else
            # Skip other types for now
          end
        end

        # Check if this is a primary volume descriptor
        #
        # @return [Boolean] true if primary VD
        def primary?
          @type == Iso::VD_PRIMARY
        end

        # Check if this is a terminator
        #
        # @return [Boolean] true if terminator
        def terminator?
          @type == Iso::VD_TERMINATOR
        end

        private

        # Parse primary volume descriptor fields
        #
        # @param data [String] Binary data
        def parse_primary_volume_descriptor(data)
          # Byte 7: Unused (0)
          # Bytes 8-39: System identifier
          @system_identifier = data[8, 32].strip

          # Bytes 40-71: Volume identifier
          @volume_identifier = data[40, 32].strip

          # Bytes 72-79: Unused (zeros)

          # Bytes 80-87: Volume space size (both-endian)
          @volume_space_size = data[80, 4].unpack1("V")

          # Bytes 88-119: Unused (zeros)

          # Bytes 120-123: Volume set size (both-endian)
          @volume_set_size = data[120, 2].unpack1("v")

          # Bytes 124-127: Volume sequence number (both-endian)
          @volume_sequence_number = data[124, 2].unpack1("v")

          # Bytes 128-131: Logical block size (both-endian)
          @logical_block_size = data[128, 2].unpack1("v")

          # Bytes 132-139: Path table size (both-endian)
          @path_table_size = data[132, 4].unpack1("V")

          # Bytes 140-143: Path table location (little-endian)
          @path_table_location = data[140, 4].unpack1("V")

          # Bytes 144-147: Optional path table location
          # Bytes 148-151: Path table location (big-endian)
          # Bytes 152-155: Optional path table location

          # Bytes 156-189: Root directory record (34 bytes)
          @root_directory_record = DirectoryRecord.parse(data[156, 34])

          # Bytes 190-317: Volume set identifier
          @volume_set_identifier = data[190, 128].strip

          # Bytes 318-445: Publisher identifier
          @publisher_identifier = data[318, 128].strip

          # Bytes 446-573: Data preparer identifier
          @preparer_identifier = data[446, 128].strip

          # Bytes 574-701: Application identifier
          @application_identifier = data[574, 128].strip

          # Bytes 702-738: Copyright file identifier
          # Bytes 739-775: Abstract file identifier
          # Bytes 776-812: Bibliographic file identifier

          # Bytes 813-829: Volume creation date/time
          @creation_date = parse_datetime(data[813, 17])

          # Bytes 830-846: Volume modification date/time
          @modification_date = parse_datetime(data[830, 17])

          # Bytes 847-863: Volume expiration date/time
          # Bytes 864-880: Volume effective date/time

          # Byte 881: File structure version
          # Bytes 882-1395: Application use
          # Bytes 1396-2047: Reserved
        end

        # Parse ISO 9660 datetime format
        #
        # @param data [String] 17-byte datetime string
        # @return [Time, nil] Parsed time or nil if invalid
        def parse_datetime(data)
          return nil if data.nil? || data.bytesize < 17

          year = data[0, 4].to_i
          month = data[4, 2].to_i
          day = data[6, 2].to_i
          hour = data[8, 2].to_i
          minute = data[10, 2].to_i
          second = data[12, 2].to_i
          # Centiseconds at 14-15 (ignored)
          # Timezone offset at 16 (ignored for now)

          return nil if year.zero?

          Time.new(year, month, day, hour, minute, second)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
