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

require_relative "match_finder"
require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible match finder adapter
      #
      # Wraps existing MatchFinder to provide XZ Utils interface with:
      # - Cursor-based position tracking
      # - Multiple match finding (not just longest)
      # - Skip and lookahead operations
      #
      # Based on: xz/src/liblzma/lz/lz_encoder_mf.c
      class XzMatchFinderAdapter
        include Constants

        # Match structure matching XZ Utils
        Match = Struct.new(:len, :dist, keyword_init: true) do
          def to_s
            "Match(len=#{len}, dist=#{dist})"
          end
        end

        attr_reader :matches, :longest_len, :pos

        # Initialize match finder adapter
        #
        # @param data [String, Array<Integer>] Input data
        # @param dict_size [Integer] Dictionary size (default 8MB for XZ)
        # @param nice_len [Integer] Nice match length (default 32)
        def initialize(data, dict_size: 1 << 23, nice_len: 32)
          @data = data.is_a?(String) ? data.bytes : data
          @pos = 0
          @dict_size = dict_size
          @nice_len = nice_len

          # Internal state
          @matches = []
          @longest_len = 0

          # Hash table for match finding
          @hash_table = {}
        end

        # Find all matches at current position
        #
        # Finds multiple matches of different lengths, not just the longest.
        # Results stored in @matches array, longest length in @longest_len.
        #
        # @return [Integer] Longest match length (0 if no matches)
        def find_matches
          @matches.clear
          @longest_len = 0

          return 0 if @pos >= @data.size
          return 0 if available < MATCH_LEN_MIN

          # CRITICAL: Don't produce matches until there's enough data for decoder
          # The decoder validates: dict_full > distance
          # Where dict_full = decoded_byte_count (starting from 0)
          # So for distance=N to be valid, we need at least N+1 bytes decoded
          # We're at position @pos (0-based), so @pos bytes have been processed
          # For distance=1 match: need @pos >= 2 (so decoder has dict_full=2)
          # For distance=N match: need @pos >= N+1
          # Simple check: Don't produce matches until @pos >= 2
          return 0 if @pos < 2

          # Find matches using hash chains
          hash_val = compute_hash
          positions = @hash_table[hash_val] || []

          # Track best matches at each length
          best_distances = {}

          positions.reverse_each do |prev_pos|
            distance = @pos - prev_pos
            break if distance > @dict_size

            # Skip self-matching (can happen when lookahead searches same position twice)
            next if distance.zero?

            match_len = calculate_match_length(prev_pos)
            next if match_len < MATCH_LEN_MIN

            # Keep best (shortest) distance for each length
            if !best_distances[match_len] || distance < best_distances[match_len]
              best_distances[match_len] = distance
            end

            # Update longest
            @longest_len = match_len if match_len > @longest_len

            # Stop if we found nice length
            break if match_len >= @nice_len
          end

          # Convert to matches array (sorted by length)
          best_distances.keys.sort.each do |len|
            @matches << Match.new(len: len, dist: best_distances[len])
          end

          # Update hash table
          update_hash(hash_val, @pos)

          @longest_len
        end

        # Skip n bytes without finding matches
        #
        # Advances position and updates hash tables but doesn't search for matches.
        # Used for rep matches where we already know what to encode.
        #
        # @param n [Integer] Number of bytes to skip
        def skip(n)
          n.times do
            return if @pos >= @data.size

            hash_val = compute_hash
            update_hash(hash_val, @pos)
            @pos += 1
          end
        end

        # Move position forward by one byte
        def move_pos
          @pos += 1
        end

        # Bytes available from current position
        #
        # @return [Integer] Number of bytes remaining
        def available
          @data.size - @pos
        end

        # Get current byte at position
        #
        # @return [Integer, nil] Byte value or nil if at end
        def current_byte
          return nil if @pos >= @data.size

          @data[@pos]
        end

        # Get byte at offset from current position
        #
        # @param offset [Integer] Offset from current position (can be negative)
        # @return [Integer] Byte value (0 if out of bounds)
        def get_byte(offset)
          pos = @pos + offset
          return 0 if pos.negative? || pos >= @data.size

          @data[pos]
        end

        # Reset match finder to beginning
        def reset
          @pos = 0
          @matches.clear
          @longest_len = 0
          @hash_table.clear
        end

        private

        # Compute hash value for sequence at current position
        #
        # @return [Integer] Hash value
        def compute_hash
          return 0 if @pos + 2 >= @data.size

          (@data[@pos] << 16) ^ (@data[@pos + 1] << 8) ^ @data[@pos + 2]
        end

        # Calculate match length between current position and previous position
        #
        # @param prev_pos [Integer] Previous position to compare against
        # @return [Integer] Length of match
        def calculate_match_length(prev_pos)
          max_len = [available, @nice_len].min
          length = 0

          while length < max_len && @data[@pos + length] == @data[prev_pos + length]
            length += 1
          end

          length
        end

        # Update hash table with position
        #
        # @param hash_val [Integer] Hash value
        # @param pos [Integer] Position to add
        def update_hash(hash_val, pos)
          @hash_table[hash_val] ||= []
          @hash_table[hash_val] << pos

          # Keep hash chains from growing too large
          @hash_table[hash_val].shift if @hash_table[hash_val].size > 1024
        end
      end
    end
  end
end
