# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        # Variable-length integer encoding/decoding for RAR5 format
        module VINT
          # Encode integer as VINT bytes per the RAR 5.0 spec: one or
          # more bytes, each carrying 7 data bits starting with the
          # least significant group; the high bit of every byte but
          # the last is the continuation flag.
          #
          # @param value [Integer] Value to encode (0 to 2^63)
          # @return [Array<Integer>] VINT bytes
          def self.encode(value)
            raise ArgumentError, "VINT cannot encode negative values" if value.negative?

            bytes = []
            loop do
              byte = value & 0x7F
              value >>= 7
              byte |= 0x80 if value.positive?
              bytes << byte
              break if value.zero?
            end

            bytes
          end

          # Decode VINT from IO stream (spec encoding, mirroring
          # BlockParser#read_vint)
          #
          # @param io [IO] Input stream
          # @return [Integer] Decoded value
          def self.decode(io)
            result = 0
            shift = 0
            loop do
              byte = io.readbyte
              result |= (byte & 0x7F) << shift
              break if byte.nobits?(0x80)

              shift += 7
            end

            result
          end
        end
      end
    end
  end
end
