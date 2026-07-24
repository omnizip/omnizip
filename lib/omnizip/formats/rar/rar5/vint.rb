# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        # Variable-length integer encoding/decoding for RAR5 format
        module VINT
          # Encode integer as VINT bytes
          # @param value [Integer] Value to encode (0 to 2^62)
          # @return [Array<Integer>] VINT bytes
          def self.encode(value)
            return [value] if value < 0x80

            bytes = []
            # Determine byte count needed
            byte_count = 1
            test_value = value
            while test_value >= (1 << (7 * byte_count))
              byte_count += 1
            end

            # First byte: continuation bits + high bits
            first_byte = (0xFF << (9 - byte_count)) & 0xFF
            first_byte |= (value >> (8 * (byte_count - 1))) & 0x7F
            bytes << first_byte

            # Remaining bytes
            (byte_count - 1).downto(1) do |i|
              bytes << ((value >> (8 * (i - 1))) & 0xFF)
            end

            bytes
          end

          # Decode VINT from IO stream
          # @param io [IO] Input stream
          # @return [Integer] Decoded value
          def self.decode(io)
            first_byte = io.readbyte
            return first_byte if first_byte < 0x80

            # Count continuation bits
            byte_count = 0
            mask = 0x80
            while first_byte.anybits?(mask)
              byte_count += 1
              mask >>= 1
            end

            # Extract value from first byte
            value = first_byte & (0xFF >> (byte_count + 1))

            # Read remaining bytes
            byte_count.times do
              value = (value << 8) | io.readbyte
            end

            value
          end
        end
      end
    end
  end
end
