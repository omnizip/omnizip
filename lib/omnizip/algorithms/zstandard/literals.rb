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
  module Algorithms
    class Zstandard
      # Literals section decoder (RFC 8878 §3.1.1.3.1).
      #
      # Header byte 0 layout (bits numbered from the LSB, matching the C
      # reference `litEncType = istart[0] & 3`):
      #
      #   bits 0-1  Literals_Block_Type (0=Raw, 1=RLE, 2=Compressed,
      #             3=Treeless)
      #   bits 2-3  Size_Format selector
      #
      # Raw / RLE size formats:
      #   00, 10 -> 1-byte header, regen = byte0 >> 3
      #   01     -> 2-byte header, regen = LE16 >> 4
      #   11     -> 3-byte header, regen = LE24 >> 4
      #
      # Compressed / Treeless size formats:
      #   00 -> 3-byte header, single stream, 10-bit sizes
      #   01 -> 3-byte header, 4 streams, 10-bit sizes
      #   10 -> 4-byte header, 4 streams, 14-bit sizes
      #   11 -> 5-byte header, 4 streams, 18-bit sizes
      class LiteralsDecoder
        include Constants

        # @return [String] decoded literal bytes
        attr_reader :literals

        # @return [Huffman, nil] table from a Compressed block, for the
        #   next Treeless block in the same frame
        attr_reader :huffman_table

        # @return [Integer] bytes consumed from the input
        attr_reader :consumed

        # Decode the literals section at the head of `input`.
        #
        # @param input [String]
        # @param previous_table [Huffman, nil] table from the previous
        #   compressed literals block (required for Treeless)
        # @return [LiteralsDecoder]
        def self.decode(input, previous_table = nil)
          raise Omnizip::DecompressionError, "empty literals section" if input.empty?

          block_type = input.getbyte(0) & 0x03

          case block_type
          when LITERALS_BLOCK_RAW then decode_raw(input)
          when LITERALS_BLOCK_RLE then decode_rle(input)
          when LITERALS_BLOCK_COMPRESSED
            decode_compressed(input, previous_table, false)
          when LITERALS_BLOCK_TREELESS
            decode_compressed(input, previous_table, true)
          end
        end

        def self.decode_raw(input)
          regen_size, header_size = size_format_raw_rle(input)
          end_pos = header_size + regen_size
          if input.bytesize < end_pos
            raise Omnizip::DecompressionError,
                  "truncated raw literals: need #{end_pos} bytes"
          end

          new(input.byteslice(header_size, regen_size), nil, end_pos)
        end

        def self.decode_rle(input)
          regen_size, header_size = size_format_raw_rle(input)
          if input.bytesize < header_size + 1
            raise Omnizip::DecompressionError,
                  "truncated RLE literals: missing repeated byte"
          end

          byte = input.getbyte(header_size)
          new(byte.chr * regen_size, nil, header_size + 1)
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def self.decode_compressed(input, previous_table, is_repeat)
          if is_repeat && previous_table.nil?
            raise Omnizip::DecompressionError,
                  "treeless literals block requires a previous compressed " \
                  "block in the same frame"
          end

          lhl_code = (input.getbyte(0) >> 2) & 0x03

          min_header = [3, 3, 4, 5][lhl_code]
          if input.bytesize < min_header
            raise Omnizip::DecompressionError,
                  "truncated compressed literals header: need #{min_header} bytes"
          end

          lit_size, lit_c_size, lh_size, single_stream =
            case lhl_code
            when 0, 1
              lhc = input.getbyte(0) |
                (input.getbyte(1) << 8) | (input.getbyte(2) << 16)
              [(lhc >> 4) & 0x3FF, (lhc >> 14) & 0x3FF, 3, lhl_code.zero?]
            when 2
              lhc = input.unpack1("V") & 0xFFFFFFFF
              [(lhc >> 4) & 0x3FFF, lhc >> 18, 4, false]
            else
              low = input.byteslice(0, 4).unpack1("V")
              high = input.getbyte(4)
              lhc = low | (high << 32)
              [(lhc >> 4) & 0x3FFFF, lhc >> 22, 5, false]
            end

          needed = lh_size + lit_c_size
          if input.bytesize < needed
            raise Omnizip::DecompressionError,
                  "truncated compressed literals: need #{needed} bytes"
          end
          compressed = input.byteslice(lh_size, lit_c_size)

          table_bytes = 0
          table = previous_table
          unless is_repeat
            table, table_bytes = HuffmanTableReader.read(compressed)
          end

          literal_data = compressed.byteslice(table_bytes..)
          literals = if single_stream
                       decode_single_stream(table, literal_data, lit_size)
                     else
                       decode_four_stream(table, literal_data, lit_size)
                     end

          new(literals, is_repeat ? nil : table, needed)
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize

        # rubocop:disable Metrics/AbcSize
        def self.size_format_raw_rle(input)
          lhl_code = (input.getbyte(0) >> 2) & 0x03
          header_size = [1, 2, 1, 3][lhl_code]
          if input.bytesize < header_size
            raise Omnizip::DecompressionError,
                  "truncated Raw/RLE literals header: need #{header_size} bytes"
          end

          case lhl_code
          when 0, 2
            [input.getbyte(0) >> 3, 1]
          when 1
            [input.unpack1("v") >> 4, 2]
          else
            lhc = input.getbyte(0) | (input.getbyte(1) << 8) |
              (input.getbyte(2) << 16)
            [lhc >> 4, 3]
          end
        end
        # rubocop:enable Metrics/AbcSize

        # One reverse bitstream decoded into lit_size symbols.
        def self.decode_single_stream(table, src, lit_size)
          bs = FSE::BitStream.new(src)
          out = String.new(encoding: Encoding::BINARY)
          lit_size.times do
            out << table.decode(bs).chr
            bs.reload
          end
          out
        end

        # Jump table + four independent reverse bitstreams, each decoding
        # ~1/4 of the literals (RFC 8878 §3.1.1.3.1.4).
        # rubocop:disable Metrics/AbcSize
        def self.decode_four_stream(table, src, lit_size)
          if src.bytesize < 10
            raise Omnizip::DecompressionError,
                  "4-stream literals too short (need at least 10 bytes)"
          end
          # rubocop:enable Metrics/AbcSize

          length1 = src.unpack1("v")
          length2 = src.byteslice(2, 2).unpack1("v")
          length3 = src.byteslice(4, 2).unpack1("v")
          total = src.bytesize - 6
          if length1 + length2 + length3 > total
            raise Omnizip::DecompressionError,
                  "4-stream jump table sizes exceed total stream size"
          end

          streams = src.byteslice(6..)
          seg1 = streams.byteslice(0, length1)
          seg2 = streams.byteslice(length1, length2)
          seg3 = streams.byteslice(length1 + length2, length3)
          seg4 = streams.byteslice((length1 + length2 + length3)..)

          segment_size = (lit_size + 3) / 4
          bounds = [0,
                    segment_size,
                    segment_size * 2,
                    segment_size * 3,
                    lit_size]

          out = String.new(encoding: Encoding::BINARY)
          [seg1, seg2, seg3, seg4].each_with_index do |seg, i|
            bs = FSE::BitStream.new(seg)
            (bounds[i]...bounds[i + 1]).each do
              out << table.decode(bs).chr
              bs.reload
            end
          end
          out
        end

        def initialize(literals, huffman_table, consumed)
          @literals = literals
          @huffman_table = huffman_table
          @consumed = consumed
        end
      end
    end
  end
end
