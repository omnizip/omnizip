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
      module FSE
        # 2-state interleaved FSE stream decoder (RFC 8878 §4.2.1.2,
        # "FSE compression of Huffman weights"; mirrors the C reference
        # FSE_decompress_usingDTable).
        #
        # Symbols are produced until the bitstream overflows; after an
        # overflow following one state's transition, one final symbol is
        # decoded from the other state without transitioning.
        module Interleaved
          module_function

          # Decode a 2-state interleaved FSE stream.
          #
          # @param table [Table]
          # @param bitstream_bytes [String]
          # @param max_output [Integer] cap on decoded length (corrupt
          #   input protection)
          # @return [Array<Integer>] decoded symbols
          def decode_stream(table, bitstream_bytes, max_output)
            bs = BitStream.new(bitstream_bytes)
            accuracy_log = table.accuracy_log

            s1 = bs.read_bits(accuracy_log)
            bs.reload
            s2 = bs.read_bits(accuracy_log)
            bs.reload

            out = []

            loop do
              check_length!(out, max_output)
              e1 = table[s1]
              out << e1.symbol
              s1 = e1.baseline + bs.read_bits(e1.num_bits)

              if bs.reload_status == BitStream::OVERFLOW
                check_length!(out, max_output)
                out << table[s2].symbol
                break
              end

              check_length!(out, max_output)
              e2 = table[s2]
              out << e2.symbol
              s2 = e2.baseline + bs.read_bits(e2.num_bits)

              if bs.reload_status == BitStream::OVERFLOW
                check_length!(out, max_output)
                out << table[s1].symbol
                break
              end
            end

            out
          end

          def check_length!(out, max_output)
            return unless out.length >= max_output

            raise Omnizip::DecompressionError,
                  "FSE decode exceeded max output #{max_output}"
          end
        end
      end
    end
  end
end
