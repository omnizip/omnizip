# frozen_string_literal: true

module Omnizip
  module Formats
    module Xz
      # XZ stream footer
      #
      # The stream footer is 12 bytes:
      # - CRC32 of backward size and stream flags (4 bytes)
      # - Backward size (4 bytes) - size of index in 4-byte blocks
      # - Stream flags (2 bytes) - must match header
      # - Footer magic (2 bytes): "YZ" (0x59 0x5A)
      class StreamFooter
        # Footer magic bytes
        MAGIC = "YZ"

        # Footer size
        SIZE = 12

        attr_reader :check_type, :backward_size

        # Initialize stream footer
        #
        # @param check_type [Integer] Check type (must match header)
        # @param backward_size [Integer] Index size in 4-byte blocks
        def initialize(check_type = 1, backward_size = 0)
          @check_type = check_type
          @backward_size = backward_size
        end

        # Encode stream footer to bytes
        #
        # @return [String] Encoded footer
        def encode
          # Backward size and stream flags
          data = [@backward_size, 0x00, @check_type].pack("V C C")

          # Calculate CRC32
          crc32 = Zlib.crc32(data)

          # Combine: CRC32 + data + magic
          [crc32].pack("V") + data + MAGIC
        end

        # Decode stream footer from bytes
        #
        # @param data [String] Footer bytes
        # @return [StreamFooter] Decoded footer
        def self.decode(data)
          raise Error, "Invalid XZ stream footer size" if data.bytesize < SIZE

          # Verify magic
          magic = data[-2, 2]
          unless magic == MAGIC
            raise Error, "Invalid XZ footer magic bytes"
          end

          # Extract data
          crc32_expected = data[0, 4].unpack1("V")
          backward_size, reserved, check_type = data[4, 6].unpack("V C C")

          # Verify CRC32
          crc32_actual = Zlib.crc32(data[4, 6])

          unless crc32_expected == crc32_actual
            raise Error, "XZ stream footer CRC32 mismatch"
          end

          new(check_type, backward_size)
        end
      end
    end
  end
end