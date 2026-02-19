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

require_relative "match"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Match Finder using hash chain algorithm for LZ77 compression
      # Ported from XZ Utils lz_encoder.c
      class MatchFinder
        HASH_SIZE = 4096
        MAX_MATCHES = 274

        attr_reader :dictionary, :buffer, :position

        def initialize(dictionary)
          @dictionary = dictionary
          @buffer = String.new(encoding: Encoding::BINARY)
          @position = 0
          # Use nil as empty marker (not 0) to distinguish from position 0
          @hash_table = Array.new(HASH_SIZE, nil)
          @hash_chain = Array.new(0)
          @matches = Array.new(MAX_MATCHES)
          @matches_count = 0
        end

        # Add input data for processing
        #
        # @param data [String] Binary data to add
        # @return [void]
        def feed(data)
          @buffer << data
        end

        # Reset the match finder state for a new encoding session
        # Clears the buffer, hash table, and hash chain
        def reset
          @buffer.clear
          @position = 0
          @hash_table = Array.new(HASH_SIZE, nil)
          @hash_chain.clear
          @matches_count = 0
        end

        # Initialize hash table for all positions up to end_pos
        # This is called before encoding starts to ensure the hash table
        # is populated for all positions. Matches XZ Utils "skip" behavior.
        #
        # @param end_pos [Integer] Last position to initialize (inclusive)
        # @return [void]
        def skip(end_pos)
          pos = 0
          while pos + 3 <= @buffer.bytesize && pos <= end_pos
            hash = calc_hash(@buffer, pos)
            if hash
              @hash_chain[pos] = @hash_table[hash]
              @hash_table[hash] = pos
            end
            pos += 1
          end
        end

        # Find matches for current position
        #
        # @param current_pos [Integer] Position to find matches at (defaults to end)
        # @return [Array<Match>] Array of matches sorted by length (descending)
        def find_matches(current_pos = @buffer.bytesize - 273)
          # Calculate hash for current position
          hash = nil
          if current_pos >= 0 && current_pos + 3 <= @buffer.bytesize
            hash = calc_hash(@buffer, current_pos)
          end

          # Update hash table for current position (even for early positions)
          # This ensures positions 0-3 are available for later matches
          # XZ Utils calls this "skip" - update hash without finding matches
          # CRITICAL: Only update if this position hasn't been processed yet
          # (i.e., @hash_table[hash] != current_pos)
          # This prevents overwriting the hash chain when find_matches is called
          # after skip() has already initialized the hash table
          if hash && @hash_table[hash] != current_pos
            @hash_chain[current_pos] = @hash_table[hash]
            @hash_table[hash] = current_pos
          end

          # Can't find matches if no hash or insufficient data
          # Note: We CAN find matches at early positions (e.g., position 2 can match position 0)
          # The only requirement is that there's enough data for hash calculation (current_pos + 3 <= buffer size)
          # and that there's at least 2 bytes of history (for MIN_MATCH_LENGTH=2)
          # CRITICAL: Don't produce matches until position >= 2 to ensure decoder has enough dict_full
          # The decoder validates: dict_full > distance, where dict_full starts at 0 after 1st byte
          # For distance=1 match to be valid, decoder needs dict_full >= 2 (at least 2 bytes decoded)
          # This happens after processing position 1 (first byte was literal at position 0)
          # So we can only produce matches starting at position 2
          return [] if hash.nil? || @buffer.bytesize < 4 || current_pos + 3 > @buffer.bytesize || current_pos < 2

          @matches_count = 0
          chain_pos = @hash_chain[current_pos]

          while chain_pos && @matches_count < MAX_MATCHES
            # CRITICAL: Skip invalid chain_pos values (beyond buffer or negative)
            next if chain_pos >= @buffer.bytesize || chain_pos.negative?

            distance = current_pos - chain_pos
            # CRITICAL: Break if distance is negative (chain_pos > current_pos)
            # This can happen when skip() links positions within the same chunk
            # where a later position has the same hash as an earlier position
            break if distance.negative? || distance > @dictionary.size || distance.zero?

            length = verify_match(current_pos, chain_pos)

            if length >= 2
              @matches[@matches_count] = Match.new(distance, length)
              @matches_count += 1
            end

            # Safely get next chain position
            chain_pos = if chain_pos < @hash_chain.size
                          @hash_chain[chain_pos]
                        end
          end

          @matches.first(@matches_count).sort_by { |m| -m.length }
        end

        # Get the longest match at current position
        #
        # @return [Match, nil] Longest match found or nil
        def longest_match
          find_matches.first
        end

        # Legacy API: Find longest match at given position in external byte array
        # This is a compatibility method for older code that passes bytes and position
        #
        # @param bytes [Array<Integer>] Byte array
        # @param pos [Integer] Position to find match at
        # @return [Match, nil] Longest match found or nil
        def find_longest_match(bytes, pos)
          # If position is beyond current buffer, feed more data
          if pos >= @buffer.bytesize
            bytes_to_feed = bytes[pos..]
            @buffer << bytes_to_feed.pack("C*")
          end

          # Find matches at the given position
          matches = find_matches(pos)
          matches.first
        end

        private

        # Calculate hash for position (first 3 bytes)
        #
        # @param data [String] Buffer data
        # @param pos [Integer] Position to hash
        # @return [Integer] Hash value
        def calc_hash(data, pos)
          return 0 if pos + 3 > data.bytesize

          (data.getbyte(pos) |
           (data.getbyte(pos + 1) << 8) |
           (data.getbyte(pos + 2) << 16)) % HASH_SIZE
        end

        # Verify match length between two positions
        #
        # @param pos1 [Integer] First position
        # @param pos2 [Integer] Second position
        # @return [Integer] Match length
        def verify_match(pos1, pos2)
          max_len = [273, @buffer.bytesize - pos1, @buffer.bytesize - pos2].min
          length = 0

          while length < max_len &&
              @buffer.getbyte(pos1 + length) == @buffer.getbyte(pos2 + length)
            length += 1
          end

          length
        end
      end
    end
  end
end
