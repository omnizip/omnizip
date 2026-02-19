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

require "stringio"
require "zlib"
require_relative "vli"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Index decoder
      #
      # Index format:
      # - Index Indicator: 0x00 (1 byte as VLI)
      # - Number of Records: VLI
      # - Records (repeated):
      #   - Unpadded Size: VLI
      #   - Uncompressed Size: VLI
      # - Padding: 0-3 bytes to align to 4-byte boundary
      # - CRC32: 4 bytes of index + padding
      #
      # Reference: /tmp/xz-source/src/liblzma/common/index_decoder.c
      class IndexDecoder
        # Index indicator byte
        INDEX_INDICATOR = 0x00

        # Minimum Unpadded Size (per XZ spec)
        UNPADDED_SIZE_MIN = 5

        # Maximum Unpadded Size (must be 4-byte aligned, so clear lowest 2 bits)
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/index.h
        UNPADDED_SIZE_MAX = VLI::MAX_VALUE & ~3

        # Parse index from input stream
        #
        # @param input [IO] Input stream positioned at index start
        # @return [Hash] Parsed index data with keys:
        #   - count: Integer (number of records)
        #   - records: Array of {unpadded_size: Integer, uncompressed_size: Integer}
        #   - index_size: Integer (total index size in bytes including padding)
        #   - stored_crc: Integer (CRC32 from file)
        # @raise [RuntimeError] If index is invalid or CRC mismatch
        def self.parse(input)
          # Track the start position for CRC calculation
          index_data = StringIO.new
          index_data.set_encoding(Encoding::BINARY)

          # Read index indicator (must be 0x00)
          # Per XZ spec (Section 4.1): "The value of Index Indicator is always 0x00"
          # The Index Indicator is stored as a VLI, but since 0x00 has no continuation
          # bit, it's always encoded as a single byte. We must read it as a single byte
          # to properly detect corruption (e.g., multi-byte VLI starting with 0xDD).
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/index_hash.c:191-193
          indicator = input.getbyte
          if indicator.nil?
            raise FormatError, "Unexpected end of stream in index indicator"
          end

          if indicator != INDEX_INDICATOR
            raise FormatError,
                  "Invalid index indicator: expected 0x00, got 0x#{indicator.to_s(16).upcase}"
          end

          # Write indicator to buffer for CRC calculation (as single byte)
          # Must use array to avoid converting to character
          index_data.write([indicator].pack("C"))

          # Read number of records
          num_records = VLI.decode(input)
          index_data.write(VLI.encode(num_records))

          if num_records > 1_000_000_000
            raise FormatError,
                  "Suspiciously large number of index records: #{num_records}"
          end

          # Read records
          records = []
          num_records.times do |_i|
            unpadded_size = VLI.decode(input)
            index_data.write(VLI.encode(unpadded_size))

            # Validate unpadded size (per XZ Utils index_decoder.c:130-133)
            if unpadded_size < UNPADDED_SIZE_MIN || unpadded_size > UNPADDED_SIZE_MAX
              raise FormatError,
                    "Invalid unpadded size: #{unpadded_size} " \
                    "(must be between #{UNPADDED_SIZE_MIN} and #{UNPADDED_SIZE_MAX})"
            end

            uncompressed_size = VLI.decode(input)
            index_data.write(VLI.encode(uncompressed_size))

            # Validate uncompressed size against VLI maximum (per XZ spec Section 1.2)
            # VLI values are limited to 63 bits to keep the encoded size at 9 bytes or less
            if uncompressed_size > VLI::MAX_VALUE
              raise FormatError,
                    "Invalid uncompressed size: #{uncompressed_size} " \
                    "(exceeds VLI maximum #{VLI::MAX_VALUE})"
            end

            records << {
              unpadded_size: unpadded_size,
              uncompressed_size: uncompressed_size,
            }
          end

          # Calculate padding needed to align to 4-byte boundary
          index_size_before_padding = index_data.pos
          padding_needed = (4 - (index_size_before_padding % 4)) % 4

          # Read padding
          padding = input.read(padding_needed) || ""
          if padding.bytesize < padding_needed
            raise FormatError, "Unexpected end of stream in index padding"
          end

          # Validate that padding bytes are all null (per XZ Utils index_decoder.c:160)
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/index_decoder.c:157-163
          # "Index Padding MUST contain only null bytes" (XZ spec Section 4.1)
          unless padding.bytes.all?(&:zero?)
            raise FormatError,
                  "Index padding contains non-null bytes: #{padding.bytes.map { |b| '0x%02x' % b }.join(', ')}"
          end

          # Add padding to index data for CRC calculation
          index_data.write(padding)

          # Read and verify CRC32
          stored_crc_bytes = input.read(4)
          if stored_crc_bytes.nil? || stored_crc_bytes.bytesize < 4
            raise FormatError, "Unexpected end of stream in index CRC32"
          end

          stored_crc = stored_crc_bytes.unpack1("V")

          # Calculate CRC32 over index data (including padding)
          actual_crc = Zlib.crc32(index_data.string)

          if actual_crc != stored_crc
            raise FormatError,
                  "Index CRC mismatch: expected #{stored_crc}, got #{actual_crc}"
          end

          {
            count: num_records,
            records: records,
            index_size: index_data.pos + 4, # +4 for CRC itself
            stored_crc: stored_crc,
          }
        end
      end
    end
  end
end
