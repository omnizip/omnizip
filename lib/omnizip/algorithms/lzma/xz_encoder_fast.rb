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

require_relative "xz_match_finder_adapter"
require_relative "xz_state"
require_relative "xz_probability_models"
require_relative "xz_buffered_range_encoder"
require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible fast mode encoder
      #
      # Implements greedy heuristics from lzma_encoder_optimum_fast.c.
      # Uses 1-position lookahead to decide between literals and matches.
      # No price calculation - relies on simple heuristics for speed.
      #
      # Based on: xz/src/liblzma/lzma/lzma_encoder_optimum_fast.c
      class XzEncoderFast
        include Constants

        # Number of rep distances (REPS constant)
        REPS = 4

        # Literal marker (matches XZ Utils UINT32_MAX)
        LITERAL_MARKER = 0xFFFFFFFF

        attr_reader :reps

        # Return bytes needed for decoding (excludes flush padding)
        #
        # For LZMA2: returns pre-flush position (excludes 5-byte flush padding)
        # For regular LZMA: returns full output size
        #
        # @return [Integer] Number of bytes decoder will consume
        def bytes_for_decode
          @encoder.bytes_for_decode
        end

        # Initialize fast mode encoder
        #
        # @param mf [XzMatchFinderAdapter] Match finder
        # @param encoder [XzBufferedRangeEncoder] Range encoder
        # @param models [XzProbabilityModels] Probability models
        # @param state [XzState] LZMA state machine
        # @param nice_len [Integer] Nice match length (default 32)
        # @param lc [Integer] Literal context bits (default 3)
        # @param lp [Integer] Literal position bits (default 0)
        # @param pb [Integer] Position bits (default 2)
        def initialize(mf, encoder, models, state, nice_len: 32, lc: 3, lp: 0,
                                                   pb: 2)
          @mf = mf
          @encoder = encoder
          @models = models
          @state = state
          @nice_len = nice_len
          @lc = lc
          @lp = lp
          @pb = pb

          # Rep distances (last 4 match distances)
          # Initialize to 0 to prevent false matches before first normal match
          @reps = [0, 0, 0, 0]

          # Lookahead cache (for read_ahead == 1 optimization)
          @read_ahead = 0
          @longest_match_length = 0
          @matches_count = 0
          @cached_matches = []

          # Track previous byte for literal context
          @prev_byte = 0
        end

        # Find best match at current position using fast mode heuristics
        #
        # Returns (back, len) where:
        # - back = LITERAL_MARKER, len = 1: encode literal
        # - back = 0..3, len >= 2: rep match (use reps[back])
        # - back >= 4, len >= 2: normal match (distance = back - 4)
        #
        # @return [Array<Integer, Integer>] [back, len]
        def find_best_match
          # Get matches (use cached if lookahead was done)
          if @read_ahead.zero?
            len_main = @mf.find_matches
            matches_count = @mf.matches.size
          else
            # Use cached matches from previous lookahead
            len_main = @longest_match_length
            matches_count = @matches_count
            @read_ahead = 0
          end

          buf_avail = [@mf.available + 1, MATCH_LEN_MAX].min

          # Not enough input for match
          return [LITERAL_MARKER, 1] if buf_avail < 2

          # Check rep matches
          rep_len, rep_index = check_rep_matches(buf_avail)

          # Found long rep match - return immediately
          if rep_len >= @nice_len
            # Don't skip here - main loop handles it
            return [rep_index, rep_len]
          end

          # Found long normal match - return immediately
          if len_main >= @nice_len
            back_main = @mf.matches.last.dist - 1 + REPS # Convert to 0-based then add REPS offset
            # Don't skip here - main loop handles it
            return [back_main, len_main]
          end

          # Select best normal match using heuristics
          back_main = 0
          if len_main >= 2
            back_main = @mf.matches.last.dist

            # Apply change_pair heuristic: prefer closer distances
            while matches_count > 1 &&
                len_main == @mf.matches[matches_count - 2].len + 1
              prev_dist = @mf.matches[matches_count - 2].dist
              break unless change_pair?(prev_dist, back_main)

              matches_count -= 1
              len_main = @mf.matches[matches_count - 1].len
              back_main = @mf.matches[matches_count - 1].dist
            end

            # Reject short matches with far distances
            len_main = 1 if len_main == 2 && back_main >= 0x80
          end

          # Compare rep vs normal match
          # Prefer rep match if:
          # - rep_len + 1 >= len_main, OR
          # - rep_len + 2 >= len_main AND back_main > 512, OR
          # - rep_len + 3 >= len_main AND back_main > 32768
          if (rep_len >= 2) && ((rep_len + 1 >= len_main) ||
                                (rep_len + 2 >= len_main && back_main > (1 << 9)) ||
                                (rep_len + 3 >= len_main && back_main > (1 << 15)))
            # Don't skip here - main loop handles it
            return [rep_index, rep_len]
          end

          # No good match found
          return [LITERAL_MARKER, 1] if len_main < 2 || buf_avail <= 2

          # Lookahead: check next position for better match
          @longest_match_length = @mf.find_matches
          @matches_count = @mf.matches.size
          @read_ahead = 1

          if @longest_match_length >= 2
            new_dist = @mf.matches.last.dist

            # Encode literal if next position has better match
            if (@longest_match_length >= len_main && new_dist < back_main) ||
                (@longest_match_length == len_main + 1 && !change_pair?(
                  back_main, new_dist
                )) ||
                (@longest_match_length > len_main + 1) ||
                (len_main.between?(3, @longest_match_length + 1) &&
                 change_pair?(new_dist, back_main))
              return [LITERAL_MARKER, 1]
            end
          end

          # Check reps at next position (after lookahead)
          # Skip if all distances are 0 (uninitialized - before first normal match)
          unless @reps.all?(0)
            limit = [2, len_main - 1].max
            @reps.each do |rep_dist|
              if memcmp_at_offset(1, rep_dist, limit)
                return [LITERAL_MARKER, 1]
              end
            end
          end

          # Encode best normal match
          # Don't skip here - main loop handles it
          # back_main contains raw 1-based distance, convert to back value
          [back_main - 1 + REPS, len_main] # Convert to 0-based then add REPS offset
        end

        # Update rep distances after encoding match
        #
        # @param distance [Integer] Match distance (0-based)
        def update_reps_match(distance)
          @reps = [distance, @reps[0], @reps[1], @reps[2]]
        end

        # Update rep distances after encoding rep match
        #
        # @param rep_index [Integer] Rep index (0-3)
        def update_reps_rep(rep_index)
          rep_dist = @reps[rep_index]
          @reps.delete_at(rep_index)
          @reps.unshift(rep_dist)
        end

        # Encode literal symbol
        #
        # @param symbol [Integer] Byte value to encode
        def encode_literal(symbol)
          pos_state = @mf.pos & ((1 << @pb) - 1)

          # Encode is_match bit (0 for literal)
          prob_is_match = @models.is_match[@state.value][pos_state]
          @encoder.queue_bit(prob_is_match, 0)

          # Get literal subcoder BASE index (XZ Utils literal_subcoder macro)
          # The subcoder is a flat array of 768 probability models
          literal_base = get_literal_base(@mf.pos, @prev_byte)

          if @state.literal_state?
            # Normal literal (8-bit tree)
            encode_normal_literal(literal_base, symbol)
          else
            # Matched literal (compare with match byte at rep0)
            match_byte = @mf.get_byte(-@reps[0]) # reps[0] is 0-based offset
            encode_matched_literal(literal_base, match_byte, symbol)
          end

          # Update state and prev_byte
          @state.update_literal
          @prev_byte = symbol
        end

        # Encode rep match
        #
        # @param rep_index [Integer] Rep index (0-3)
        # @param length [Integer] Match length (>= 2)
        def encode_rep_match(rep_index, length)
          pos_state = @mf.pos & ((1 << @pb) - 1)

          # Encode is_match bit (1 for match)
          prob_is_match = @models.is_match[@state.value][pos_state]
          @encoder.queue_bit(prob_is_match, 1)

          # Encode is_rep bit (1 for rep)
          prob_is_rep = @models.is_rep[@state.value]
          @encoder.queue_bit(prob_is_rep, 1)

          prob_is_rep0 = @models.is_rep0[@state.value]
          case rep_index
          when 0
            # rep0
            @encoder.queue_bit(prob_is_rep0, 0) # FIX: 0 means "yes, use rep0"

            prob_is_rep0_long = @models.is_rep0_long[@state.value][pos_state]
            if length == 1
              # Short rep (1 byte)
              @encoder.queue_bit(prob_is_rep0_long, 0)
              @state.update_short_rep
            else
              # Long rep0
              @encoder.queue_bit(prob_is_rep0_long, 1)
              encode_rep_length(length, pos_state)
              @state.update_long_rep
            end
          when 1
            # rep1
            @encoder.queue_bit(prob_is_rep0, 1)
            prob_is_rep1 = @models.is_rep1[@state.value]
            @encoder.queue_bit(prob_is_rep1, 0) # FIX: 0 means "yes, use rep1"
            encode_rep_length(length, pos_state)
            @state.update_long_rep
          when 2
            # rep2
            @encoder.queue_bit(prob_is_rep0, 1)
            prob_is_rep1 = @models.is_rep1[@state.value]
            @encoder.queue_bit(prob_is_rep1, 1)
            prob_is_rep2 = @models.is_rep2[@state.value]
            @encoder.queue_bit(prob_is_rep2, 0) # FIX: 0 means "yes, use rep2"
            encode_rep_length(length, pos_state)
            @state.update_long_rep
          else
            # rep3
            @encoder.queue_bit(prob_is_rep0, 1)
            prob_is_rep1 = @models.is_rep1[@state.value]
            @encoder.queue_bit(prob_is_rep1, 1)
            prob_is_rep2 = @models.is_rep2[@state.value]
            @encoder.queue_bit(prob_is_rep2, 1)
            encode_rep_length(length, pos_state)
            @state.update_long_rep
          end

          # Update prev_byte (last byte of match)
          @prev_byte = @mf.get_byte(length - 1)
        end

        # Encode normal match
        #
        # @param distance [Integer] Match distance (0-based)
        # @param length [Integer] Match length (>= 2)
        def encode_normal_match(distance, length)
          pos_state = @mf.pos & ((1 << @pb) - 1)

          # Encode is_match bit (1 for match)
          prob_is_match = @models.is_match[@state.value][pos_state]
          @encoder.queue_bit(prob_is_match, 1)

          # Encode is_rep bit (0 for normal match)
          prob_is_rep = @models.is_rep[@state.value]
          @encoder.queue_bit(prob_is_rep, 0)

          # Encode length
          encode_match_length(length, pos_state)

          # Encode distance
          encode_distance(distance, length)

          # Update state and prev_byte
          @state.update_match
          @prev_byte = @mf.get_byte(length - 1)
        end

        private

        # Check all rep matches at current position
        #
        # @param buf_avail [Integer] Bytes available
        # @return [Array<Integer, Integer>] [best_rep_len, best_rep_index]
        def check_rep_matches(buf_avail)
          rep_len = 0
          rep_index = 0

          # Guard: Skip rep matching if all distances are 0 (uninitialized)
          # This prevents false matches before the first normal match
          return [0, 0] if @reps.all?(0)

          @reps.each_with_index do |rep_dist, i|
            # Skip rep distances of 0 (same position, invalid)
            next if rep_dist.zero?

            # Check first 2 bytes (MATCH_LEN_MIN)
            next unless matches_at_distance?(rep_dist, MATCH_LEN_MIN)

            # Calculate full match length
            len = calculate_match_length(rep_dist, buf_avail)

            if len > rep_len
              rep_len = len
              rep_index = i
            end
          end

          [rep_len, rep_index]
        end

        # Check if first n bytes match at given distance
        #
        # @param distance [Integer] Distance to check (0-based: 0=same pos, 1=1 byte back)
        # @param n [Integer] Number of bytes to check
        # @return [Boolean] True if matches
        def matches_at_distance?(distance, n)
          return false if @mf.pos < distance

          n.times do |i|
            curr = @mf.get_byte(i)
            prev = @mf.get_byte(i - distance)
            return false if curr != prev
          end

          true
        end

        # Calculate match length at given distance
        #
        # @param distance [Integer] Distance (0-based: 0=same pos, 1=1 byte back)
        # @param max_len [Integer] Maximum length to check
        # @return [Integer] Match length
        def calculate_match_length(distance, max_len)
          return 0 if @mf.pos < distance

          len = 0

          while len < max_len
            curr = @mf.get_byte(len)
            prev = @mf.get_byte(len - distance)
            break if curr != prev

            len += 1
          end

          len
        end

        # Compare bytes at offset with bytes at distance
        #
        # Used for checking reps after lookahead.
        #
        # @param offset [Integer] Offset from current position
        # @param distance [Integer] Distance to check (1-based)
        # @param limit [Integer] Number of bytes to compare
        # @return [Boolean] True if all bytes match
        def memcmp_at_offset(offset, distance, limit)
          limit.times do |i|
            curr = @mf.get_byte(offset + i)
            prev = @mf.get_byte(offset + i - distance)
            return false if curr != prev
          end

          true
        end

        # Apply change_pair heuristic
        #
        # Prefer closer distances if far distance is much larger.
        #
        # @param small_dist [Integer] Smaller distance
        # @param big_dist [Integer] Larger distance
        # @return [Boolean] True if should change to smaller distance
        def change_pair?(small_dist, big_dist)
          (big_dist >> 7) > small_dist
        end

        # Get literal subcoder BASE index
        #
        # Ported from XZ Utils literal_subcoder() macro in lzma_common.h
        # Returns the base index into the flat literal models array
        # Each subcoder has 768 probability models (0x300)
        #
        # @param pos [Integer] Current position
        # @param prev_byte [Integer] Previous byte
        # @return [Integer] Base index into @models.literal array
        def get_literal_base(pos, prev_byte)
          # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
          literal_mask = (0x100 << @lp) - (0x100 >> @lc)

          # ((((pos) << 8) + (prev_byte)) & (literal_mask)) << (lc)
          context = (((pos << 8) + prev_byte) & literal_mask) << @lc

          # 3 * context (each subcoder has 768 models, indexed as 3 * context + offset)
          3 * context
        end

        # Encode normal literal (8-bit tree)
        #
        # @param literal_base [Integer] Base index into literal models array
        # @param symbol [Integer] Byte value
        def encode_normal_literal(literal_base, symbol)
          context = 1
          8.downto(1) do |i|
            bit = (symbol >> (i - 1)) & 1
            @encoder.queue_bit(@models.literal[literal_base + context], bit)
            context = (context << 1) | bit
          end
        end

        # Encode matched literal (compare with match byte)
        #
        # @param literal_base [Integer] Base index into literal models array
        # @param match_byte [Integer] Byte at match position
        # @param symbol [Integer] Byte value to encode
        def encode_matched_literal(literal_base, match_byte, symbol)
          offset = 0x100
          symbol += 0x100 # Start symbol at 256 (XZ Utils algorithm)

          # Loop until symbol reaches 0x10000 (65536)
          while symbol < 0x10000
            match_byte <<= 1
            match_bit = match_byte & offset
            subcoder_index = offset + match_bit + (symbol >> 8)
            bit = (symbol >> 7) & 1

            @encoder.queue_bit(@models.literal[literal_base + subcoder_index],
                               bit)

            symbol <<= 1
            offset &= ~(match_byte ^ symbol)
          end
        end

        # Encode rep match length
        #
        # @param length [Integer] Match length (>= 2)
        # @param pos_state [Integer] Position state
        def encode_rep_length(length, pos_state)
          encode_length(@models.rep_len_encoder, length, pos_state)
        end

        # Encode normal match length
        #
        # @param length [Integer] Match length (>= 2)
        # @param pos_state [Integer] Position state
        def encode_match_length(length, pos_state)
          encode_length(@models.match_len_encoder, length, pos_state)
        end

        # Encode length using length encoder
        #
        # @param len_encoder [LengthEncoder] Length encoder
        # @param length [Integer] Match length (2-273)
        # @param pos_state [Integer] Position state
        def encode_length(len_encoder, length, pos_state)
          len = length - MATCH_LEN_MIN

          if len < LEN_LOW_SYMBOLS
            # Low: 0-7
            @encoder.queue_bit(len_encoder.choice, 0)
            encode_bittree(len_encoder.low[pos_state], NUM_LEN_LOW_BITS, len)
          elsif len < LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS
            # Mid: 8-15
            @encoder.queue_bit(len_encoder.choice, 1)
            @encoder.queue_bit(len_encoder.choice2, 0)
            encode_bittree(len_encoder.mid[pos_state], NUM_LEN_MID_BITS,
                           len - LEN_LOW_SYMBOLS)
          else
            # High: 16-271
            @encoder.queue_bit(len_encoder.choice, 1)
            @encoder.queue_bit(len_encoder.choice2, 1)
            encode_bittree(len_encoder.high, NUM_LEN_HIGH_BITS,
                           len - LEN_LOW_SYMBOLS - LEN_MID_SYMBOLS)
          end
        end

        # Encode distance
        #
        # @param distance [Integer] Distance (0-based)
        # @param length [Integer] Match length
        def encode_distance(distance, length)
          dist_slot = get_dist_slot(distance)
          len_state = get_len_to_pos_state(length)

          # Encode distance slot
          encode_bittree(@models.dist_slot[len_state], NUM_DIST_SLOT_BITS,
                         dist_slot)

          # Encode distance footer
          if dist_slot >= START_POS_MODEL_INDEX
            footer_bits = (dist_slot >> 1) - 1
            base = (2 | (dist_slot & 1)) << footer_bits
            dist_reduced = distance - base

            if dist_slot < END_POS_MODEL_INDEX
              # Use probability models
              encode_bittree_reverse(@models.dist_special, dist_reduced,
                                     footer_bits, base - dist_slot)
            else
              # Direct bits + alignment
              direct_bits = footer_bits - DIST_ALIGN_BITS
              @encoder.queue_direct_bits(dist_reduced >> DIST_ALIGN_BITS,
                                         direct_bits)
              encode_bittree_reverse(@models.dist_align, dist_reduced & ((1 << DIST_ALIGN_BITS) - 1),
                                     DIST_ALIGN_BITS, 0)
            end
          end
        end

        # Encode bittree (MSB first)
        #
        # @param probs [Array<BitModel>] Probability models
        # @param num_bits [Integer] Number of bits
        # @param value [Integer] Value to encode
        def encode_bittree(probs, num_bits, value)
          context = 1
          num_bits.downto(1) do |i|
            bit = (value >> (i - 1)) & 1
            @encoder.queue_bit(probs[context], bit)
            context = (context << 1) | bit
          end
        end

        # Encode bittree in reverse (LSB first)
        #
        # @param probs [Array<BitModel>] Probability models
        # @param value [Integer] Value to encode
        # @param num_bits [Integer] Number of bits
        # @param offset [Integer] Probability array offset
        def encode_bittree_reverse(probs, value, num_bits, offset)
          context = 1
          num_bits.times do |i|
            bit = (value >> i) & 1
            @encoder.queue_bit(probs[offset + context], bit)
            context = (context << 1) | bit
          end
        end

        # Get distance slot for distance
        #
        # @param distance [Integer] Distance (0-based)
        # @return [Integer] Distance slot (0-63)
        def get_dist_slot(distance)
          if distance < NUM_FULL_DISTANCES
            # Use precomputed table for small distances
            distance < 4 ? distance : fast_pos_small(distance)
          else
            # Formula for large distances
            fast_pos_large(distance)
          end
        end

        # Fast position calculation for small distances
        def fast_pos_small(distance)
          # Simplified slot calculation
          slot = 0
          dist = distance
          while dist > 3
            dist >>= 1
            slot += 2
          end
          slot + dist
        end

        # Fast position calculation for large distances
        def fast_pos_large(distance)
          slot = fast_pos_small(distance >> 6)
          slot + 12
        end

        # Map length to position state
        #
        # @param length [Integer] Match length
        # @return [Integer] Position state (0-3)
        def get_len_to_pos_state(length)
          len = length - MATCH_LEN_MIN
          len < NUM_LEN_TO_POS_STATES ? len : NUM_LEN_TO_POS_STATES - 1
        end
      end
    end
  end
end
