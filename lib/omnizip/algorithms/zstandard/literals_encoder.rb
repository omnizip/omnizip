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
      # Literals Section encoder (RFC 8878 §3.1.1.3.1): picks Raw, RLE
      # or Huffman-compressed, whichever is smallest.
      module LiteralsEncoder
        include Constants

        module_function

        # Encode a literals section for `literals`.
        #
        # @param literals [String]
        # @return [String] the full section (header + content)
        def encode(literals)
          return encode_raw(literals) if literals.bytesize < 16

          return encode_rle(literals) if rle?(literals)

          compressed = nil
          begin
            compressed = HuffmanEncoder.encode_literals(literals)
          rescue Omnizip::CompressionError
            compressed = nil
          end

          if compressed && compressed.bytesize < literals.bytesize
            compressed
          else
            encode_raw(literals)
          end
        end

        # Raw literals block with the minimal size-format header.
        def encode_raw(literals)
          encode_raw_rle_header(LITERALS_BLOCK_RAW, literals.bytesize) +
            literals
        end

        # RLE literals block: one byte, repeated.
        def encode_rle(literals)
          encode_raw_rle_header(LITERALS_BLOCK_RLE, literals.bytesize) +
            literals.getbyte(0).chr
        end

        def rle?(literals)
          first = literals.getbyte(0)
          idx = 1
          while idx < literals.bytesize
            return false if literals.getbyte(idx) != first

            idx += 1
          end
          true
        end

        # 1/2/3-byte Raw/RLE header per the size-format rules. For the
        # 2- and 3-byte forms the Size_Format bits (01 / 11) live in
        # bits 2-3 and the size starts at bit 4.
        def encode_raw_rle_header(type, size)
          if size < 32
            [type | (size << 3)].pack("C")
          elsif size < 4096
            lhc = type | 0x04 | (size << 4)
            [lhc & 0xFF, (lhc >> 8) & 0xFF].pack("CC")
          else
            lhc = type | 0x0C | (size << 4)
            [lhc & 0xFF, (lhc >> 8) & 0xFF, (lhc >> 16) & 0xFF].pack("CCC")
          end
        end
      end
    end
  end
end
