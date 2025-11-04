# frozen_string_literal: true

module Omnizip
  module Formats
    module Xz
      # XZ stream header
      #
      # The stream header is 12 bytes:
      # - Magic bytes (6 bytes): 0xFD 0x37 0x7A 0x58 0x5A 0x00
      # - Stream flags (2 bytes)
      # - CRC32 of stream flags (4 bytes)
      class StreamHeader
        # XZ magic bytes
        MAGIC = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].pack("C*")

        # Header size
        SIZE = 12

        attr_reader :check_type

        # Initialize stream header
        #
        # @param check_type [Integer] Check type (0=None, 1=CRC32, 4=CRC64)
        def initialize(check_type = 1)
          @check_type = check_type
        end

        # Encode stream header to bytes
        #
        # @return [String] Encoded header
        def encode
          # Stream flags: 2 bytes
          # First byte is reserved (0x00)
          # Second byte contains check type
          stream_flags = [0x00, @check_type].pack("C C")

          # Calculate CRC32 of stream flags
          crc32 = Zlib.crc32(stream_flags)

          # Combine: magic + stream_flags + CRC32
          MAGIC + stream_flags + [crc32].pack("V")
        end

        # Decode stream header from bytes
        #
        # @param data [String] Header bytes
        # @return [StreamHeader] Decoded header
        def self.decode(data)
          raise Error, "Invalid XZ stream header size" if data.bytesize < SIZE

          # Verify magic
          magic = data[0, 6]
          unless magic == MAGIC
            raise Error, "Invalid XZ magic bytes"
          end

          # Extract stream flags
          stream_flags = data[6, 2]
          reserved, check_type = stream_flags.unpack("C C")

          # Verify CRC32
          crc32_expected = data[8, 4].unpack1("V")
          crc32_actual = Zlib.crc32(stream_flags)

          unless crc32_expected == crc32_actual
            raise Error, "XZ stream header CRC32 mismatch"
          end

          new(check_type)
        end
      end
    end
  end
end