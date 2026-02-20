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
require_relative "../../checksums/verifier"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream Header parser
      #
      # Stream Header format (12 bytes):
      # - Magic: 0xFD 0x37 0x7A 0x58 0x5A 0x00 (6 bytes)
      # - Stream Flags: check_type and reserved (2 bytes)
      # - CRC32: of magic + flags (4 bytes, little-endian)
      #
      # Reference: /tmp/xz-source/src/liblzma/common/stream_header_decoder.c
      class StreamHeaderParser
        # Stream header magic bytes
        HEADER_MAGIC = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].freeze

        # Stream header size in bytes
        HEADER_SIZE = 12

        # Parse stream header from input stream
        #
        # @param input [IO] Input stream positioned at stream start
        # @return [Hash] Parsed header data with keys:
        #   - check_type: Integer (0=None, 1=CRC32, 4=CRC64, 10=SHA256)
        # @raise [RuntimeError] If header is invalid or CRC mismatch
        def self.parse(input)
          # Read 12 bytes
          header = input.read(HEADER_SIZE)
          if header.nil? || header.bytesize < HEADER_SIZE
            raise FormatError,
                  "Unexpected end of file: incomplete stream header"
          end

          # Verify magic bytes (first 6 bytes)
          magic = header[0..5].bytes
          unless magic == HEADER_MAGIC
            raise FormatError, "Invalid XZ magic bytes: got #{magic.map do |b|
              b.to_s(16).upcase
            end.join(' ')}"
          end

          # Extract stream flags (bytes 6-7)
          flags = header[6..7]

          # Byte 6: reserved (must be 0)
          if flags.getbyte(0) != 0
            raise FormatError, "Invalid stream flags: reserved byte is non-zero"
          end

          # Byte 7: check type (low 4 bits) + reserved (high 4 bits)
          check_flags = flags.getbyte(1)
          check_type = check_flags & 0x0F
          reserved = (check_flags >> 4) & 0x0F

          if reserved != 0
            raise FormatError,
                  "Invalid stream flags: reserved bits are non-zero"
          end

          # Validate check type (only 0, 1, 4, 10 are valid)
          unless [0, 1, 4, 10].include?(check_type)
            raise FormatError,
                  "Unsupported check type: #{check_type} (not supported)"
          end

          # Verify CRC32 (bytes 8-11)
          # IMPORTANT: CRC is calculated ONLY over Stream Flags (2 bytes), NOT magic!
          # Reference: /tmp/xz-source/src/liblzma/common/stream_flags_decoder.c
          crc_data = flags # Only flags, not magic
          stored_crc = header[8..11].unpack1("V")
          actual_crc = Zlib.crc32(crc_data)

          if actual_crc != stored_crc
            raise FormatError,
                  "Stream header CRC mismatch: expected #{stored_crc}, got #{actual_crc}"
          end

          { check_type: check_type }
        end
      end
    end
  end
end
