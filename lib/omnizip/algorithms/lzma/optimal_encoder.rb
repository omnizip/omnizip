# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Optimal encoder - chooses best encoding
      # Ported from lzma_encoder_optimum_fast.c
      class OptimalEncoder
        attr_reader :mode

        def initialize(mode: :fast)
          @mode = mode
        end

        # Find optimal encoding for current position
        def find_optimal(position, match_finder, state, reps, models)
          case @mode
          when :fast
            optimum_fast(position, match_finder, state, reps, models)
          else
            raise ArgumentError, "Unknown mode: #{@mode}"
          end
        end

        private

        # TODO: position, state, reps, and models parameters will be used
        # when implementing normal mode for more optimal encoding decisions
        def optimum_fast(position, match_finder, _state, reps, _models)
          buf = match_finder.buffer # CRITICAL: Use match_finder.buffer, NOT dictionary.buffer!
          buf_pos = position
          buf_avail = [buf.bytesize - buf_pos, MATCH_LEN_MAX].min

          # puts "[OPTIMUM] position=#{position} buf_avail=#{buf_avail} buf.bytesize=#{buf.bytesize}" if ENV['DEBUG']

          # Not enough input for a match
          return [UINT32_MAX, 1] if buf_avail < 2

          # CRITICAL: Check repeated matches FIRST (before normal matches)
          # This matches XZ Utils lzma_lzma_optimum_fast behavior
          rep_len = 0
          rep_index = 0

          # For level 9, nice_len = MATCH_LEN_MAX = 273
          nice_len = MATCH_LEN_MAX

          # Look for repeated matches; scan the previous four match distances
          reps.each_with_index do |rep_dist, i|
            # Pointer to the beginning of the match candidate
            # In XZ: buf_back = buf - coder->reps[i] - 1
            # In Ruby: buf_back_index = buf_pos - rep_dist - 1
            buf_back_index = buf_pos - rep_dist - 1

            # DEBUG: Trace repeated match check
            # puts "[OPTIMAL] Checking rep#{i}: rep_dist=#{rep_dist} buf_pos=#{buf_pos} buf_back_index=#{buf_back_index}" if ENV['DEBUG']

            # Skip if out of bounds
            next if buf_back_index.negative? || buf_back_index >= buf.bytesize

            # puts "[OPTIMAL] buf[#{buf_pos}]=#{'%02x' % buf.getbyte(buf_pos)} buf[#{buf_back_index}]=#{'%02x' % buf.getbyte(buf_back_index)}" if ENV['DEBUG']

            # If the first two bytes (2 == MATCH_LEN_MIN) do not match,
            # this rep is not useful.
            next if buf.getbyte(buf_pos) != buf.getbyte(buf_back_index) ||
              buf.getbyte(buf_pos + 1) != buf.getbyte(buf_back_index + 1)

            # The first two bytes matched. Calculate the length of the match.
            len = 2
            while (buf_pos + len < buf.bytesize) &&
                (buf_back_index + len < buf.bytesize) &&
                (buf.getbyte(buf_pos + len) == buf.getbyte(buf_back_index + len)) &&
                (len < MATCH_LEN_MAX) &&
                (len < buf_avail)
              len += 1
            end

            # If we have found a repeated match that is at least
            # nice_len long, return it immediately.
            if len >= nice_len
              # Return rep index (0-3 for rep0-rep3)
              return [i, len]
            end

            if len > rep_len
              rep_index = i
              rep_len = len
            end
          end

          # Find normal matches from match finder
          matches = match_finder.find_matches(position)

          # We didn't find a long enough repeated match.
          # Encode it as a normal match if the match length is at least nice_len
          # AND the match distance is within the dictionary buffer.
          best_normal = matches.max_by { |m| [m.length, m.distance] }

          if best_normal && best_normal.length >= nice_len &&
              best_normal.distance <= match_finder.dictionary.buffer.bytesize
            # CRITICAL: Only use normal match if distance is within actual dictionary buffer
            # This prevents invalid matches that reference bytes not yet written to dictionary
            # Use normal match
            return [best_normal.distance + REPS, best_normal.length]
          end

          # Compare best rep match vs best normal match
          # Prefer longer match, for equal length prefer rep match (XZ behavior)
          if rep_len >= 2 && rep_len >= (best_normal&.length || 0)
            # Use repeated match
            [rep_index, rep_len]
          elsif best_normal && best_normal.distance <= match_finder.dictionary.buffer.bytesize
            # CRITICAL: Only use normal match if distance is within actual dictionary buffer
            # Use dictionary.buffer.bytesize (actual data), NOT dictionary.size (max capacity)
            # This prevents invalid matches that reference bytes not yet written to dictionary
            [best_normal.distance + REPS, best_normal.length]
          else
            # Use literal - return UINT32_MAX to indicate literal (not 0!)
            [UINT32_MAX, 1]
          end
        end

        # Constants
        REPS = 4
        MATCH_LEN_MAX = 273 # From lzma.h
        MATCH_LEN_MIN = 2
        UINT32_MAX = 0xFFFFFFFF
      end
    end
  end
end
