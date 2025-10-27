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

require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZ77 Match Finder for dictionary compression
      #
      # This class implements hash-chain based match finding for
      # identifying duplicate sequences in the input data. It maintains
      # a sliding window dictionary and uses hash tables to efficiently
      # locate potential matches.
      #
      # The match finder operates by:
      # 1. Hashing sequences of bytes at each position
      # 2. Maintaining chains of positions with the same hash
      # 3. Searching these chains to find the longest match
      # 4. Returning match information (length, distance)
      class MatchFinder
        include Constants

        # Represents a match found in the dictionary
        class Match
          attr_reader :length, :distance

          def initialize(length, distance)
            @length = length
            @distance = distance
          end
        end

        attr_reader :window_size, :max_match_length

        # Initialize the match finder
        #
        # @param window_size [Integer] Size of sliding window
        # @param max_match_length [Integer] Maximum match length to find
        def initialize(window_size = 1 << 16,
                       max_match_length = MATCH_LEN_MAX)
          @window_size = window_size
          @max_match_length = max_match_length
          @hash_table = {}
          @hash_chain = []
        end

        # Find the longest match at the given position
        #
        # @param data [String, Array<Integer>] Input data
        # @param pos [Integer] Current position in data
        # @return [Match, nil] Best match or nil if no match found
        def find_longest_match(data, pos)
          return nil if pos >= data.size
          return nil if data.size - pos < MATCH_LEN_MIN

          best_match = nil
          best_length = MATCH_LEN_MIN - 1

          hash_val = compute_hash(data, pos)
          positions = @hash_table[hash_val] || []

          positions.reverse_each do |prev_pos|
            break if pos - prev_pos > @window_size

            match_len = calculate_match_length(data, pos, prev_pos)

            next unless match_len > best_length

            best_length = match_len
            best_match = Match.new(match_len, pos - prev_pos)
            break if best_length >= @max_match_length
          end

          update_hash(hash_val, pos)
          best_match
        end

        # Reset the match finder state
        #
        # @return [void]
        def reset
          @hash_table.clear
          @hash_chain.clear
        end

        private

        # Compute hash value for sequence starting at position
        #
        # @param data [String, Array<Integer>] Input data
        # @param pos [Integer] Position to hash from
        # @return [Integer] Hash value
        def compute_hash(data, pos)
          return 0 if pos + 2 >= data.size

          bytes = data.is_a?(String) ? data.bytes : data
          (bytes[pos] << 16) ^ (bytes[pos + 1] << 8) ^ bytes[pos + 2]
        end

        # Calculate match length between two positions
        #
        # @param data [String, Array<Integer>] Input data
        # @param pos1 [Integer] First position
        # @param pos2 [Integer] Second position
        # @return [Integer] Length of match
        def calculate_match_length(data, pos1, pos2)
          bytes = data.is_a?(String) ? data.bytes : data
          max_len = [data.size - pos1, @max_match_length].min
          length = 0

          while length < max_len && bytes[pos1 + length] ==
                                    bytes[pos2 + length]
            length += 1
          end

          length
        end

        # Update hash table with new position
        #
        # @param hash_val [Integer] Hash value
        # @param pos [Integer] Position to add
        # @return [void]
        def update_hash(hash_val, pos)
          @hash_table[hash_val] ||= []
          @hash_table[hash_val] << pos

          # Keep hash chains from growing too large
          @hash_table[hash_val].shift if @hash_table[hash_val].size >
                                         1024
        end
      end
    end
  end
end
