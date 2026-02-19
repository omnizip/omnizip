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
require_relative "constants"
require_relative "vli"
require_relative "../../error"
require_relative "../../checksums/verifier"

module Omnizip
  module Formats
    module XzFormat
      # XZ Block Header parser
      #
      # Block Header format:
      # - Block Header Size: (size_in_4byte_units - 1) encoded as 1 byte
      # - Block Flags: 1 byte (bit 7=uncompressed_size_present, bit 6=compressed_size_present, bits 0-1=num_filters)
      # - Compressed Size: VLI (if flag bit 6 is set)
      # - Uncompressed Size: VLI (if flag bit 7 is set)
      # - Filters: for each filter: id(1) + props_size(1) + properties(props_size bytes)
      # - Padding: 0-3 bytes to align to 4-byte boundary
      # - CRC32: 4 bytes of header + padding
      #
      # Reference: /tmp/xz-source/src/liblzma/common/block_header_decoder.c
      class BlockHeaderParser
        # Filter IDs (from XZ spec)
        FILTER_LZMA2 = 0x21
        FILTER_DELTA = 0x03
        FILTER_BCJ_X86 = 0x04
        FILTER_BCJ_POWERPC = 0x05
        FILTER_BCJ_IA64 = 0x06
        FILTER_BCJ_ARM = 0x07
        FILTER_BCJ_ARMTHUMB = 0x08
        FILTER_BCJ_SPARC = 0x09

        # Parse block header from input stream
        #
        # @param input [IO] Input stream positioned at block header start
        # @return [Hash] Parsed header data with keys:
        #   - compressed_size: Integer or nil
        #   - uncompressed_size: Integer or nil
        #   - filters: Array of {id: Integer, properties: String or nil}
        #   - header_size: Integer (total header size in bytes)
        # @raise [RuntimeError] If header is invalid or CRC mismatch
        def self.parse(input)
          # Read block header size byte
          size_byte = input.getbyte
          if size_byte.nil?
            raise FormatError,
                  "Unexpected end of stream in block header"
          end

          # Calculate actual header size: stored as (size / 4) - 1
          # So actual size = (stored + 1) * 4
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/api/lzma/block.h:340
          #   #define lzma_block_header_size_decode(b) (((uint32_t)(b) + 1) * 4)
          header_size = ((size_byte + 1) * 4)

          if header_size < 8 || header_size > 1024
            raise FormatError, "Invalid block header size: #{header_size}"
          end

          # Read remaining header (minus size byte)
          remaining_size = header_size - 1
          header_data = input.read(remaining_size)

          if header_data.nil? || header_data.bytesize < remaining_size
            raise FormatError, "Unexpected end of stream in block header data"
          end

          # Reconstruct full header for CRC verification
          full_header = [size_byte].pack("C") + header_data

          # CRC32 is at the end (last 4 bytes)
          crc_offset = header_size - 4
          stored_crc = full_header[crc_offset..].unpack1("V")

          # CRC data is: size_byte + header_fields + padding (but NOT the CRC itself)
          crc_data = full_header[0..(crc_offset - 1)]
          actual_crc = Zlib.crc32(crc_data)

          if actual_crc != stored_crc
            raise FormatError,
                  "Block header CRC mismatch: expected #{stored_crc}, got #{actual_crc}"
          end

          # Parse block header (excluding padding and CRC)
          parse_buffer = StringIO.new(crc_data[1..]) # Skip size byte, parse until padding

          # Parse block flags (1 byte)
          block_flags = parse_buffer.getbyte
          if block_flags.nil?
            raise FormatError,
                  "Unexpected end of block header flags"
          end

          has_compressed_size = block_flags.anybits?(0x40)
          has_uncompressed_size = block_flags.anybits?(0x80)
          # Number of filters is encoded as (num_filters - 1) in bits 0-1
          num_filters = (block_flags & 0x03) + 1

          # Parse compressed size (VLI, if present)
          compressed_size = nil
          if has_compressed_size
            compressed_size = VLI.decode(parse_buffer)
          end

          # Parse uncompressed size (VLI, if present)
          uncompressed_size = nil
          if has_uncompressed_size
            uncompressed_size = VLI.decode(parse_buffer)
          end

          # Parse filters
          filters = []
          num_filters.times do
            # Filter ID is stored as VLI (can be multi-byte for custom filters)
            # But standard filters are single-byte values
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/filter_common.c:44-52
            filter_id = VLI.decode(parse_buffer)

            # Validate filter ID against XZ spec
            # Standard filter IDs: 0x01-0x04 are reserved for 7z compatibility (invalid for XZ)
            # Valid XZ filters: 0x03 (Delta), 0x04-0x0B (BCJ filters), 0x21 (LZMA2)
            # Reference: xz-file-format-1.2.1.txt Section 5.4.1
            if filter_id < 0x03 || (filter_id > 0x0B && filter_id < 0x21)
              raise FormatError,
                    "Unsupported or invalid filter ID: 0x#{filter_id.to_s(16).upcase}"
            end

            # Reserved custom filter range (>= 0x4000000000000000) is invalid
            if filter_id >= 0x4000_0000_0000_0000
              raise FormatError,
                    "Invalid reserved custom filter ID: 0x#{filter_id.to_s(16).upcase}"
            end

            props_size = parse_buffer.getbyte
            if props_size.nil?
              raise FormatError,
                    "Unexpected end of stream in filter props size"
            end

            properties = if props_size.positive?
                           props_data = parse_buffer.read(props_size)
                           if props_data.nil? || props_data.bytesize < props_size
                             raise FormatError,
                                   "Unexpected end of stream in filter properties"
                           end

                           props_data
                         end

            filters << { id: filter_id, properties: properties }
          end

          {
            compressed_size: compressed_size,
            uncompressed_size: uncompressed_size,
            filters: filters,
            header_size: header_size,
          }
        end
      end
    end
  end
end
