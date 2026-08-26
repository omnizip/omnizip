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
      # Burrows-Wheeler Transform (BWT)
      #
      # The BWT is a block-sorting compression algorithm that
      # rearranges a character string into runs of similar characters.
      # This transformation is reversible and forms the foundation of
      # the BZip2 compression algorithm.
      #
      # The transformation works by:
      # 1. Creating all rotations of the input string
      # 2. Sorting these rotations lexicographically
      # 3. Taking the last column of the sorted rotations
      # 4. Recording the row index of the original string
      #
      # This groups similar characters together, making the data
      # more compressible for subsequent stages (MTF, RLE, Huffman).
      class Bwt
        # Encode data using Burrows-Wheeler Transform (optimized)
        #
        # @param data [String] Input data to transform
        # @return [Array<String, Integer>] Transformed data and primary idx
        def encode(data)
          return ["".b, 0] if data.empty?

          n = data.length
          bytes = data.bytes

          # Doubled bytes: rotation a's byte at offset o is
          # dbl[a + o] — indexing needs no modulo, and comparisons
          # can run 8 bytes at a time (modulo arithmetic in the
          # comparator dominated the encoder's profile).
          dbl = bytes * 2

          # Build suffix array without creating rotation strings
          suffix_array = (0...n).to_a
          suffix_array.sort! do |a, b|
            compare_rotations(dbl, a, b, n)
          end

          # Find primary index (position where suffix starts at 0)
          primary_index = suffix_array.index(0)

          # Extract last column (character before each suffix)
          transformed = suffix_array.map do |idx|
            dbl[n + idx - 1]
          end.pack("C*").b

          [transformed, primary_index]
        end

        # Decode data using reverse Burrows-Wheeler Transform
        #
        # @param data [String] Transformed data (last column)
        # @param primary_index [Integer] Index of original string
        # @return [String] Original data
        def decode(data, primary_index)
          return "".b if data.empty?

          # Build LF (Last-to-First) mapping
          # This maps each position in L to corresponding position in F
          lf = build_lf_mapping(data)

          # Reconstruct by following the LF chain. The first column
          # is the sorted last column — sort ONCE (the previous code
          # re-sorted inside the loop, making decode O(n^2 log n)).
          first_column = data.bytes.sort
          result = []
          idx = primary_index

          data.length.times do
            result << first_column[idx]
            idx = lf[idx]
          end

          result.pack("C*").b
        end

        # Build LF (Last-to-First) mapping for BWT decode
        #
        # For each position i in the sorted order (first column),
        # LF[i] tells us which position in the sorted order corresponds
        # to the same character in the last column
        #
        # @param last_column [String] Last column (transformed data)
        # @return [Array<Integer>] LF mapping array
        def build_lf_mapping(last_column)
          n = last_column.length

          # Count occurrences of each byte value
          counts = Array.new(256, 0)
          last_column.each_byte { |b| counts[b] += 1 }

          # Build cumulative counts (start position of each byte in sorted array)
          cumulative = Array.new(256, 0)
          sum = 0
          256.times do |i|
            cumulative[i] = sum
            sum += counts[i]
          end

          # Build the LF mapping
          # For each position in last column, find its position in first column
          lf = Array.new(n)
          occurrence = Array.new(256, 0) # Track which occurrence of each byte

          last_column.each_byte.with_index do |byte, i|
            # This byte's position in first column is:
            # cumulative[byte] + occurrence[byte]
            pos_in_first = cumulative[byte] + occurrence[byte]
            occurrence[byte] += 1

            # Now find which last column position corresponds to this first column position
            # We need the inverse: which last column index has this sorted position
            lf[pos_in_first] = i
          end

          lf
        end

        private

        # Compare two rotations without creating strings
        # This is the key optimization - avoids O(n²) memory allocation
        #
        # @param bytes [Array<Integer>] Byte array
        # @param a [Integer] First rotation start index
        # @param b [Integer] Second rotation start index
        # @param n [Integer] Length
        # @return [Integer] -1, 0, or 1 for comparison result
        # Compare rotations a and b over the doubled byte array.
        # Four big-endian bytes per step: the chunk fits a Fixnum (no
        # Bignum allocation), the low-offset byte dominates so the
        # order is lexicographic, and the doubled array removes the
        # per-byte modulo.
        def compare_rotations(dbl, a, b, n)
          len = 0
          while len + 4 <= n
            wa = (dbl[a + len] << 24) |
              (dbl[a + len + 1] << 16) |
              (dbl[a + len + 2] << 8) |
              dbl[a + len + 3]
            wb = (dbl[b + len] << 24) |
              (dbl[b + len + 1] << 16) |
              (dbl[b + len + 2] << 8) |
              dbl[b + len + 3]
            return wa <=> wb if wa != wb

            len += 4
          end
          while len < n
            cmp = dbl[a + len] <=> dbl[b + len]
            return cmp if cmp != 0

            len += 1
          end
          0
        end

        # Build next array for BWT decode
        #
        # The next array tells us where each character in the last
        # column appears in the first column, taking duplicates into
        # account using stable counting.
        #
        # @param last_column [String] Last column (transformed data)
        # @return [Array<Integer>] Next array
        def build_next_array(last_column)
          n = last_column.length

          # Count character frequencies
          counts = Array.new(256, 0)
          last_column.each_byte { |b| counts[b] += 1 }

          # Calculate cumulative sums (positions in first column)
          cumulative = Array.new(256, 0)
          sum = 0
          256.times do |i|
            cumulative[i] = sum
            sum += counts[i]
          end

          # Build next array
          next_array = Array.new(n)
          last_column.each_byte.with_index do |byte, i|
            next_array[i] = cumulative[byte]
            cumulative[byte] += 1
          end

          next_array
        end

        # Reconstruct original string using next array
        #
        # @param first_column [String] First column (sorted)
        # @param next_array [Array<Integer>] Next positions
        # @param primary_index [Integer] Starting position
        # @return [String] Original string
        def reconstruct_from_next(first_column, next_array, primary_index)
          result = []
          idx = primary_index

          first_column.length.times do
            result << first_column.getbyte(idx)
            idx = next_array[idx]
          end

          result.pack("C*").b
        end
      end
    end
  end
end
