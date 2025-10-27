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
    class BZip2 < Algorithm
      # Move-to-Front (MTF) Transform
      #
      # MTF is a data transformation that exploits locality of reference.
      # It maintains a list of symbols and moves accessed symbols to the
      # front of the list. This tends to concentrate frequently accessed
      # symbols at low indices, making the data more compressible.
      #
      # After BWT, the data often has runs of the same character. MTF
      # converts these to runs of low numbers (often 0), which are then
      # efficiently compressed by RLE.
      #
      # The algorithm:
      # 1. Initialize symbol list [0, 1, 2, ..., 255]
      # 2. For each byte in input:
      #    - Find its position in the symbol list
      #    - Output that position
      #    - Move the byte to the front of the list
      class Mtf
        # Encode data using Move-to-Front transform
        #
        # @param data [String] Input data to transform
        # @return [String] MTF-encoded data (byte indices)
        def encode(data)
          return "".b if data.empty?

          symbols = init_symbol_list
          result = []

          data.each_byte do |byte|
            # Find position of byte in symbol list
            index = symbols.index(byte)
            result << index

            # Move byte to front
            symbols.delete_at(index)
            symbols.unshift(byte)
          end

          result.pack("C*")
        end

        # Decode MTF-encoded data
        #
        # @param data [String] MTF-encoded indices
        # @return [String] Original data
        def decode(data)
          return "".b if data.empty?

          symbols = init_symbol_list
          result = []

          data.each_byte do |index|
            # Get byte at this index
            byte = symbols[index]
            result << byte

            # Move byte to front
            symbols.delete_at(index)
            symbols.unshift(byte)
          end

          result.pack("C*")
        end

        private

        # Initialize symbol list with all possible byte values
        #
        # @return [Array<Integer>] Symbol list [0, 1, 2, ..., 255]
        def init_symbol_list
          (0..255).to_a
        end
      end
    end
  end
end
