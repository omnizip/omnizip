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

require "zlib"
require_relative "constants"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream Footer parser
      #
      # Stream Footer format (12 bytes):
      # - CRC32: of backward_size + flags (4 bytes, little-endian)
      # - Backward Size: size of Index in 4-byte units (4 bytes, little-endian)
      # - Stream Flags: same as in Stream Header (2 bytes)
      # - Magic: 0x59 0x5A (2 bytes)
      #
      # Reference: /tmp/xz-source/src/liblzma/common/stream_footer_decoder.c
      class StreamFooterParser
        # Stream footer magic bytes (reverse of header magic)
        FOOTER_MAGIC = [0x59, 0x5A].freeze

        # Stream footer size in bytes
        FOOTER_SIZE = 12

        # Parse stream footer from input stream
        #
        # @param input [IO] Input stream positioned at footer start
        # @return [Hash] Parsed footer data with keys:
        #   - backward_size: Integer (size of Index in 4-byte units)
        #   - check_type: Integer (0=None, 1=CRC32, 4=CRC64, 10=SHA256)
        # @raise [RuntimeError] If footer is invalid or CRC mismatch
        def self.parse(input)
          # Read 12 bytes
          footer = input.read(FOOTER_SIZE)
          if footer.nil? || footer.bytesize < FOOTER_SIZE
            raise FormatError,
                  "Unexpected end of file: incomplete stream footer"
          end

          # Verify magic bytes (last 2 bytes)
          magic = footer[-2..].bytes
          unless magic == FOOTER_MAGIC
            raise FormatError, "Invalid XZ footer magic: got #{magic.map do |b|
              b.to_s(16).upcase
            end.join(' ')}"
          end

          # Parse CRC32 (first 4 bytes)
          stored_crc = footer[0..3].unpack1("V")

          # Parse backward size (next 4 bytes, little-endian)
          backward_size = footer[4..7].unpack1("V")

          # Parse stream flags (next 2 bytes)
          flags = footer[8..9]

          # Byte 8: reserved (must be 0)
          if flags.getbyte(0) != 0
            raise FormatError,
                  "Invalid stream footer: reserved byte is non-zero"
          end

          # Byte 9: check type (low 4 bits) + reserved (high 4 bits)
          check_flags = flags.getbyte(1)
          check_type = check_flags & 0x0F
          reserved = (check_flags >> 4) & 0x0F

          if reserved != 0
            raise FormatError,
                  "Invalid stream footer: reserved bits are non-zero"
          end

          # Validate check type
          unless [0, 1, 4, 10].include?(check_type)
            raise FormatError, "Invalid check type in footer: #{check_type}"
          end

          # Verify CRC32
          # CRC is calculated over backward_size + flags (bytes 4-9)
          crc_data = footer[4..9]
          actual_crc = Zlib.crc32(crc_data)

          if actual_crc != stored_crc
            raise FormatError,
                  "Stream footer CRC mismatch: expected #{stored_crc}, got #{actual_crc}"
          end

          {
            backward_size: backward_size,
            check_type: check_type,
          }
        end
      end
    end
  end
end
