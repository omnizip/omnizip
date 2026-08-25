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
      # Long-Distance Matching sparse hash table (port of the
      # omnizip-rs encoder/ldm.rs).
      #
      # Hashes every `gap`-th position into a head/chain table so the
      # parser can find matches at distances far beyond the normal
      # match-finder window — up to the full frame size. The table is
      # pre-populated over the whole input before parsing starts, so
      # entries may point forward of the current position; find_match
      # skips those without spending its chain budget.
      class LdmHashTable
        # Chain entries walked per find_match (Rust LDM_MAX_CHAIN).
        LDM_MAX_CHAIN = 32
        MIN_MATCH = MatchFinder::MIN_MATCH

        # Hash table and chain sizes are additionally capped by the
        # number of sparse samples so small inputs do not pay for a
        # window-sized table.
        def initialize(input_len, window_log, gap = 16)
          samples = (input_len / gap) + 1
          hash_log = [[window_log, 21].min, samples.bit_length + 2].min
          hash_log = 1 if hash_log < 1

          @gap = gap
          @hash_log = hash_log
          @head = Array.new(1 << hash_log)
          @chain = Array.new(samples)
        end

        # Insert `pos` into the table (sparse sampling: every gap-th
        # position only).
        def insert(src, pos)
          return unless (pos % @gap).zero?

          h = hash4(src, pos)
          idx = pos / @gap
          @chain[idx] = @head[h] if idx < @chain.length
          @head[h] = pos
        end

        # Longest match at `pos` within `max_distance`, bounded by
        # `end_bound` (the current block end). Walks up to MAX_CHAIN
        # chain entries. Returns [distance, length] or nil.
        #
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable-next Metrics/CyclomaticComplexity
        def find_match(src, pos, max_distance, min_match, end_bound)
          return nil if pos + MIN_MATCH > src.bytesize

          candidate = @head[hash4(src, pos)]
          best_len = 0
          best_dist = 0
          chain_count = 0

          while candidate && chain_count < LDM_MAX_CHAIN
            if candidate >= pos
              candidate = @chain[candidate / @gap]
              next
            end

            dist = pos - candidate
            break if dist > max_distance

            len_cap = [end_bound - pos, pos - candidate].min
            len_cap = 0 if len_cap.negative?
            len = MatchFinder.count_match(src, pos, src, candidate, len_cap)
            if len > best_len && len >= min_match
              best_len = len
              best_dist = dist
            end

            candidate = @chain[candidate / @gap]
            chain_count += 1
          end

          return nil unless best_len >= min_match && best_dist.positive?

          [best_dist, best_len]
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        private

        # rubocop:disable-next Metrics/AbcSize
        def hash4(src, pos)
          v = src.getbyte(pos) |
            (src.getbyte(pos + 1) << 8) |
            (src.getbyte(pos + 2) << 16) |
            (src.getbyte(pos + 3) << 24)
          ((v * MatchFinder::PRIME4_BYTES) & 0xFFFFFFFF) >> (32 - @hash_log)
        end
      end
    end
  end
end
