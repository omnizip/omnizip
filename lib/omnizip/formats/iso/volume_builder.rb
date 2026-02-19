# frozen_string_literal: true

require "time"
require_relative "../iso"

module Omnizip
  module Formats
    module Iso
      # ISO 9660 Volume Descriptor Builder
      #
      # Builds primary and supplementary volume descriptors for ISO images.
      # Handles proper encoding of volume metadata and root directory information.
      class VolumeBuilder
        # @return [String] Volume identifier
        attr_reader :volume_id

        # @return [String] System identifier
        attr_reader :system_id

        # @return [String] Publisher
        attr_reader :publisher

        # @return [String] Preparer
        attr_reader :preparer

        # @return [String] Application
        attr_reader :application

        # @return [Integer] ISO level
        attr_reader :level

        # @return [Boolean] Rock Ridge enabled
        attr_reader :rock_ridge

        # @return [Boolean] Joliet enabled
        attr_reader :joliet

        # Initialize volume builder
        #
        # @param options [Hash] Builder options
        def initialize(options = {})
          @volume_id = options.fetch(:volume_id, "OMNIZIP")
          @system_id = options.fetch(:system_id, "LINUX")
          @publisher = options.fetch(:publisher, "")
          @preparer = options.fetch(:preparer, "")
          @application = options.fetch(:application, "OMNIZIP")
          @level = options.fetch(:level, 2)
          @rock_ridge = options.fetch(:rock_ridge, false)
          @joliet = options.fetch(:joliet, false)
        end

        # Build primary volume descriptor
        #
        # @param root_dir [Hash] Root directory information
        # @return [String] Primary VD sector (2048 bytes)
        def build_primary(root_dir)
          sector = +""

          # Byte 0: Volume descriptor type (1 = Primary)
          sector << [Iso::VD_PRIMARY].pack("C")

          # Bytes 1-5: Standard identifier "CD001"
          sector << VolumeDescriptor::ISO_IDENTIFIER

          # Byte 6: Version (1)
          sector << [1].pack("C")

          # Byte 7: Unused (0)
          sector << "\x00"

          # Bytes 8-39: System identifier (a-characters, space-padded)
          sector << pad_a_string(@system_id, 32)

          # Bytes 40-71: Volume identifier (d-characters, space-padded)
          sector << pad_d_string(@volume_id, 32)

          # Bytes 72-79: Unused (zeros)
          sector << ("\x00" * 8)

          # Bytes 80-87: Volume space size (both-endian)
          volume_sectors = root_dir[:total_sectors] || 100
          sector << [volume_sectors].pack("V") # Little-endian
          sector << [volume_sectors].pack("N") # Big-endian

          # Bytes 88-119: Unused (zeros)
          sector << ("\x00" * 32)

          # Bytes 120-123: Volume set size (both-endian)
          sector << [1].pack("v")
          sector << [1].pack("n")

          # Bytes 124-127: Volume sequence number (both-endian)
          sector << [1].pack("v")
          sector << [1].pack("n")

          # Bytes 128-131: Logical block size (both-endian)
          sector << [Iso::SECTOR_SIZE].pack("v")
          sector << [Iso::SECTOR_SIZE].pack("n")

          # Bytes 132-139: Path table size (both-endian)
          path_table_size = root_dir[:path_table_size] || 10
          sector << [path_table_size].pack("V")
          sector << [path_table_size].pack("N")

          # Bytes 140-143: Location of type L path table
          sector << [root_dir[:path_table_location] || 19].pack("V")

          # Bytes 144-147: Location of optional type L path table
          sector << [0].pack("V")

          # Bytes 148-151: Location of type M path table
          sector << [root_dir[:path_table_location_be] || 20].pack("N")

          # Bytes 152-155: Location of optional type M path table
          sector << [0].pack("N")

          # Bytes 156-189: Root directory record (34 bytes)
          sector << build_root_directory_record(root_dir)

          # Bytes 190-317: Volume set identifier
          sector << pad_d_string("", 128)

          # Bytes 318-445: Publisher identifier
          sector << pad_a_string(@publisher, 128)

          # Bytes 446-573: Data preparer identifier
          sector << pad_a_string(@preparer, 128)

          # Bytes 574-701: Application identifier
          sector << pad_a_string(@application, 128)

          # Bytes 702-738: Copyright file identifier
          sector << pad_d_string("", 37)

          # Bytes 739-775: Abstract file identifier
          sector << pad_d_string("", 37)

          # Bytes 776-812: Bibliographic file identifier
          sector << pad_d_string("", 37)

          # Bytes 813-829: Volume creation date/time
          now = Time.now
          sector << encode_volume_datetime(now)

          # Bytes 830-846: Volume modification date/time
          sector << encode_volume_datetime(now)

          # Bytes 847-863: Volume expiration date/time (not set)
          sector << encode_volume_datetime(nil)

          # Bytes 864-880: Volume effective date/time (not set)
          sector << encode_volume_datetime(nil)

          # Byte 881: File structure version (1)
          sector << [1].pack("C")

          # Byte 882: Unused (0)
          sector << "\x00"

          # Bytes 883-1395: Application use
          sector << ("\x00" * 513)

          # Bytes 1396-2047: Reserved
          sector << ("\x00" * 652)

          sector
        end

        # Build Joliet supplementary volume descriptor
        #
        # @param root_dir [Hash] Root directory information
        # @return [String] Joliet SVD sector (2048 bytes)
        def build_joliet(root_dir)
          # Joliet is similar to primary VD but with:
          # - Type = 2 (supplementary)
          # - UCS-2 encoding for strings
          # - Escape sequences for character set

          sector = build_primary(root_dir)

          # Modify type to supplementary
          sector.setbyte(0, Iso::VD_SUPPLEMENTARY)

          # Add escape sequences for UCS-2
          # Bytes 88-90: %/@  %/C  %/E for levels 1, 2, 3
          sector.setbyte(88, 0x25)  # '%'
          sector.setbyte(89, 0x2F)  # '/'
          sector.setbyte(90, 0x45)  # 'E'

          # Convert volume ID to UCS-2
          volume_id_ucs2 = @volume_id.encode("UTF-16BE")
          padded_volume_id = pad_string(volume_id_ucs2,
                                        32).force_encoding("ASCII-8BIT")

          # Replace bytes 40-71 with UCS-2 volume ID
          32.times do |i|
            sector.setbyte(40 + i, padded_volume_id.getbyte(i))
          end

          sector
        end

        private

        # Build root directory record
        #
        # @param root_dir [Hash] Root directory info
        # @return [String] 34-byte directory record
        def build_root_directory_record(root_dir)
          record = +""

          # Length of record (34 bytes for root)
          record << [34].pack("C")

          # Extended attribute length (0)
          record << [0].pack("C")

          # Location of extent (both-endian)
          location = root_dir[:location] || 21
          record << [location].pack("V")
          record << [location].pack("N")

          # Data length (both-endian)
          data_length = root_dir[:size] || Iso::SECTOR_SIZE
          record << [data_length].pack("V")
          record << [data_length].pack("N")

          # Recording date
          record << encode_record_datetime(Time.now)

          # Flags (directory)
          record << [Iso::FLAG_DIRECTORY].pack("C")

          # File unit size, interleave gap
          record << [0, 0].pack("C2")

          # Volume sequence number (both-endian)
          record << [1].pack("v")
          record << [1].pack("n")

          # File identifier length (1 for root)
          record << [1].pack("C")

          # File identifier (0x00 for root)
          record << "\x00"

          record
        end

        # Encode volume date/time (17-byte format)
        #
        # @param time [Time, nil] Time to encode
        # @return [String] 17-byte encoded time
        def encode_volume_datetime(time)
          if time.nil?
            # All zeros for unset time
            return "#{'0' * 16}\u0000"
          end

          format(
            "%04d%02d%02d%02d%02d%02d%02d",
            time.year,
            time.month,
            time.day,
            time.hour,
            time.min,
            time.sec,
            0, # Centiseconds
          ) + [0].pack("c") # GMT offset
        end

        # Encode recording date/time (7-byte format)
        #
        # @param time [Time] Time to encode
        # @return [String] 7-byte encoded time
        def encode_record_datetime(time)
          [
            time.year - 1900,
            time.month,
            time.day,
            time.hour,
            time.min,
            time.sec,
            0, # GMT offset
          ].pack("C7")
        end

        # Pad string with spaces (a-characters)
        #
        # @param str [String] String to pad
        # @param length [Integer] Target length
        # @return [String] Padded string
        def pad_a_string(str, length)
          str = str[0, length] if str.bytesize > length
          str + (" " * (length - str.bytesize))
        end

        # Pad string with spaces (d-characters)
        #
        # @param str [String] String to pad
        # @param length [Integer] Target length
        # @return [String] Padded string
        def pad_d_string(str, length)
          pad_a_string(str, length)
        end

        # Pad generic string
        #
        # @param str [String] String to pad
        # @param length [Integer] Target length
        # @return [String] Padded string
        def pad_string(str, length)
          str = str[0, length] if str.bytesize > length
          padding = "\x00".encode(str.encoding) * (length - str.bytesize)
          str + padding
        end
      end
    end
  end
end
