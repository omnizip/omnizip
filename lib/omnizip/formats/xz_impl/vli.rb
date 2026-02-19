# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

module Omnizip
  module Formats
    module XzFormat
      # Variable-Length Integer (VLI) codec for XZ format
      #
      # XZ format uses VLIs extensively for encoding sizes and counts.
      # Each byte has the format: 0xxxxxxx (continue) or 1xxxxxxx (last)
      # Maximum value is 2^63 - 1 (63 bits of data)
      #
      # Reference: /tmp/xz-source/src/liblzma/common/vli_decoder.c
      module VLI
        # Maximum VLI value (63 bits, as per XZ spec)
        MAX_VALUE = (1 << 63) - 1

        # Decode a VLI from input stream
        #
        # @param input [IO] Input stream
        # @return [Integer] Decoded value
        # @raise [Omnizip::IOError, Omnizip::FormatError] If VLI is invalid or exceeds maximum
        def self.decode(input)
          result = 0
          shift = 0
          byte_count = 0

          loop do
            byte = input.getbyte
            if byte.nil?
              raise Omnizip::IOError,
                    "Unexpected end of stream in VLI"
            end
            byte_count += 1

            if shift >= 63
              raise Omnizip::FormatError,
                    "VLI overflow (shift=#{shift}, max=63)"
            end

            # Add lower 7 bits to result
            result |= (byte & 0x7F) << shift

            # Check if continuation bit is set
            break if byte.nobits?(0x80)

            shift += 7
          end

          if result > MAX_VALUE
            raise Omnizip::FormatError,
                  "VLI exceeds maximum (#{result} > #{MAX_VALUE})"
          end

          # XZ spec: VLIs must use minimum encoding
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/vli_decoder.c:77-83
          # If more than 1 byte was used, the value must be large enough to require it
          # For example, value 13 can be encoded as 0x0D (1 byte) but NOT as 0x8D 0x00 (2 bytes)
          if byte_count > 1 && result < (1 << (7 * (byte_count - 1)))
            raise FormatError,
                  "VLI not minimally encoded: value #{result} uses #{byte_count} bytes, " \
                  "but minimum is #{size(result)} bytes"
          end

          result
        end

        # Encode a value as VLI (for testing and validation)
        #
        # @param value [Integer] Value to encode
        # @return [String] Encoded bytes
        # @raise [Omnizip::FormatError] If value exceeds maximum
        def self.encode(value)
          if value > MAX_VALUE
            raise Omnizip::FormatError,
                  "VLI value #{value} exceeds maximum #{MAX_VALUE}"
          end

          bytes = []
          loop do
            byte = value & 0x7F
            value >>= 7

            # Set continuation bit if more bytes remain
            byte |= 0x80 if value.positive?

            bytes << byte
            break if value.zero?
          end
          bytes.pack("C*")
        end

        # Calculate encoded size of a VLI value
        #
        # @param value [Integer] Value to measure
        # @return [Integer] Number of bytes needed to encode
        def self.size(value)
          size = 1
          value >>= 7
          while value.positive?
            size += 1
            value >>= 7
          end
          size
        end
      end
    end
  end
end
