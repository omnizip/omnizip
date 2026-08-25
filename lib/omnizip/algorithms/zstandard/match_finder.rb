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
      # LZ77 match finder for Zstandard (port of the omnizip-rs
      # encoder/match_finder.rs, itself from zstd_compress_lazy /
      # zstd_fast in the C reference).
      #
      # Uses a 4-byte multiplicative hash table with optional hash-chain
      # walking, over ABSOLUTE positions of the whole input so matches
      # can reference earlier blocks (window permitting). Parsers:
      # greedy (no look-ahead), lazy (1-step), lazy2 (2-step).
      module MatchFinder
        include Constants

        PRIME4_BYTES = 2_654_435_761
        MIN_MATCH = 4
        # Matches shorter than this cost more to encode than the
        # literals they replace under a greedy/lazy parse (measured in
        # the Rust port: min_match 3 regressed ~20% vs 5).
        MIN_MATCH_ECONOMICAL = 5
        REP_NUM = 3

        RawSequence = Struct.new(:literal_length, :match_length, :offset)

        # Literal buffer + raw sequences produced by the match finder.
        class SeqStore
          # @return [String] all literal bytes
          attr_accessor :literals

          # @return [Array<RawSequence>]
          attr_accessor :sequences

          # @return [Array<Integer>] finder-side repeat offsets
          attr_accessor :rep_offsets

          def initialize(rep_offsets = [1, 4, 8])
            @literals = String.new(encoding: Encoding::BINARY)
            @sequences = []
            @rep_offsets = rep_offsets
          end
        end

        # Persistent hash table (and optional chain) shared by all
        # blocks of a frame. Positions are absolute offsets into the
        # input; the table is NOT cleared between blocks.
        class MatchState
          include Constants

          attr_reader :hash_table, :chain, :max_chain
          attr_accessor :hash_log

          def initialize(hash_log)
            @hash_log = hash_log
            @hash_table = Array.new(1 << hash_log, 0)
            @chain = []
            @max_chain = 0
          end

          def enable_chain(max_chain)
            @max_chain = max_chain
            return unless max_chain.positive? && @chain.empty?

            @chain = Array.new(BLOCK_MAX_SIZE + 1, 0)
          end

          def disable_chain
            @max_chain = 0
          end

          # Seed the hash table with a prefix's positions (dictionary
          # content prepended to the plaintext): the most recent
          # position per hash wins, matching insert order.
          def seed_prefix(src, prefix_len)
            return if prefix_len < MIN_MATCH

            limit = prefix_len - MIN_MATCH + 1
            (0...limit).each do |pos|
              @hash_table[MatchFinder.hash4(src, pos, @hash_log)] = pos
            end
          end
        end

        module_function

        # Parameters for a compression level (a Ruby-sized adaptation
        # of the C ZSTD_defaultCParameters table): the hash log is
        # additionally capped by the input size so small inputs do not
        # pay for a huge table.
        #
        # @return [Hash] with :hash_log, :chain, :lazy, :min_match
        def params_for_level(level, input_len)
          level = level.clamp(1, 22)
          input_log = input_len.positive? ? input_len.bit_length - 1 : 6
          hash_log = { 1 => 12, 2 => 13, 3 => 14, 4 => 14, 5 => 14,
                       6 => 14, 7 => 15, 8 => 15, 9 => 16, 10 => 16,
                       11 => 16, 12 => 17 }.fetch(level, 17)
          hash_log = input_log if input_log < hash_log
          hash_log = 6 if hash_log < 6

          lazy, chain = if level <= 5
                          [0, 0]
                        elsif level <= 7
                          [1, 4]
                        else
                          [2, [1 << [(level - 4) / 2, 4].min, 32].min]
                        end

          { hash_log: hash_log, chain: chain, lazy: lazy,
            min_match: MIN_MATCH_ECONOMICAL }
        end

        # Allocation-free little-endian reads; the hot loops call
        # these millions of times, and String#byteslice + unpack1
        # showed up as half the encoder's time via GC pressure.
        def read4(src, pos)
          src.getbyte(pos) |
            (src.getbyte(pos + 1) << 8) |
            (src.getbyte(pos + 2) << 16) |
            (src.getbyte(pos + 3) << 24)
        end

        def read8(src, pos)
          src.getbyte(pos) |
            (src.getbyte(pos + 1) << 8) |
            (src.getbyte(pos + 2) << 16) |
            (src.getbyte(pos + 3) << 24) |
            (src.getbyte(pos + 4) << 32) |
            (src.getbyte(pos + 5) << 40) |
            (src.getbyte(pos + 6) << 48) |
            (src.getbyte(pos + 7) << 56)
        end

        def hash4(src, pos, h_bits)
          v = read4(src, pos)
          # 32-bit wrapping multiply (C/uint32_t), then the high bits.
          ((v * PRIME4_BYTES) & 0xFFFFFFFF) >> (32 - h_bits)
        end

        # Count matching bytes between two positions, 8 bytes at a
        # time (C ZSTD_count).
        def count_match(a, a_pos, b, b_pos, limit)
          len = 0
          a_size = a.bytesize
          b_size = b.bytesize
          while len + 8 <= limit && a_pos + len + 8 <= a_size &&
              b_pos + len + 8 <= b_size
            wa = read8(a, a_pos + len)
            wb = read8(b, b_pos + len)
            if wa == wb
              len += 8
            else
              diff = wa ^ wb
              return len + (((diff & -diff).bit_length - 1) / 8)
            end
          end
          while len < limit && a_pos + len < a_size && b_pos + len < b_size &&
              a.getbyte(a_pos + len) == b.getbyte(b_pos + len)
            len += 1
          end
          len
        end

        # Run the parser over src[block_start...block_end]. Positions
        # are absolute; the hash table persists across calls so
        # cross-block references are found.
        #
        # @param lazy [Integer] 0 = greedy, 1 or 2 = look-ahead steps
        # @return [void] sequences and literals are appended to seq_store
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable-next Metrics/PerceivedComplexity
        def compress_range(src, block_start, block_end, seq_store, ms,
                           min_match, lazy, ldm = nil,
                           max_distance = BLOCK_MAX_SIZE)
          mm = [min_match, MIN_MATCH_ECONOMICAL].max
          span = block_end - block_start
          if span < mm + 1
            seq_store.literals << src.byteslice(block_start, span)
            return
          end

          ms.hash_log
          anchor = block_start
          ip = block_start.positive? ? block_start : 1
          limit = block_end - mm

          while ip < limit
            match = if ldm || lazy.positive?
                      # Lazy levels share the LDM loop's rep0 fast-path
                      # (with backward extension): without it, levels
                      # 6+ measured worse than the greedy default level
                      # because every rep-offset match paid full offset
                      # coding.
                      find_match_ldm(src, ip, ms, mm, limit, anchor,
                                     seq_store.rep_offsets[0], ldm,
                                     max_distance)
                    else
                      find_greedy_match(src, ip, ms, mm, limit, anchor,
                                        seq_store.rep_offsets[0])
                    end
            if match
              dist, len = match
              defer = false
              if lazy.positive?
                (1..lazy).each do |k|
                  next unless ip + k < limit

                  m2 = if ldm
                         probe_match(src, ip + k, ms, mm, limit, ldm,
                                     max_distance)
                       else
                         probe_match(src, ip + k, ms, mm, limit)
                       end
                  if m2 && m2[1] > len + k
                    defer = true
                    break
                  end
                end
              end

              if defer
                ip += 1
                next
              end

              ip = match[2] if match.length == 3
              seq_store.literals << src.byteslice(anchor, ip - anchor)
              seq_store.sequences <<
                RawSequence.new(ip - anchor, len, dist)
              rotate_reps(seq_store.rep_offsets, dist)
              insert_range(ms, src, ip, len)
              ip += len
              anchor = ip
            else
              ip += 1
            end
          end

          return unless anchor < block_end

          seq_store.literals << src.byteslice(anchor, block_end - anchor)
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        # LDM-mode match search (port of the Rust
        # compress_block_lazy2_with_ldm loop body): rep0 fast-path
        # first, then the normal hash probe merged with the LDM
        # table. Returns [offset, length, start] or nil.
        def find_match_ldm(src, ip, ms, min_match, limit, anchor, rep0,
                           ldm, max_distance)
          m = rep0_match(src, ip, rep0, min_match, limit, anchor)
          return m if m

          dist, len = find_best_match(src, ip, ms, min_match, limit,
                                      ldm, max_distance)
          return nil unless dist

          back = backward_extension(src, ip, anchor, ip - dist)
          [dist, len + back, ip - back]
        end

        # Greedy-path match search (port of the Rust
        # compress_block_with_min_match): the rep0 fast-path first
        # (cheapest offset to encode), then the hash table — both
        # with backward extension into the pending literals. Returns
        # [offset, length, start] or nil.
        def find_greedy_match(src, ip, ms, min_match, limit, anchor, rep0)
          m = rep0_match(src, ip, rep0, min_match, limit, anchor)
          return m if m

          dist, len = find_best_match(src, ip, ms, min_match, limit)
          return nil unless dist

          back = backward_extension(src, ip, anchor, ip - dist)
          [dist, len + back, ip - back]
        end

        # Match at distance rep0 (the decoder's most recent offset)
        # with forward and backward extension. [rep0, length, start]
        # or nil.
        #
        # rubocop:disable-next Metrics/AbcSize
        def rep0_match(src, ip, rep0, min_match, limit, anchor)
          return nil if rep0 <= 0 || ip <= rep0
          return nil if read4(src, ip) != read4(src, ip - rep0)

          m_len = MIN_MATCH + count_match(
            src, ip + MIN_MATCH, src, ip + MIN_MATCH - rep0,
            [limit + MIN_MATCH_ECONOMICAL - ip - MIN_MATCH, 0].max
          )
          back = backward_extension(src, ip, anchor, ip - rep0)
          m_len += back
          return nil if m_len < min_match

          [rep0, m_len, ip - back]
        end

        # Bytes before `ip` (and before the match candidate) that
        # extend the match backward, bounded by the pending literal
        # run so the previous sequence is never overlapped.
        def backward_extension(src, ip, anchor, candidate)
          back = 0
          while ip > anchor + back && candidate > back &&
              src.getbyte(ip - 1 - back) == src.getbyte(candidate - 1 - back)
            back += 1
          end
          back
        end

        # Find the best match at `ip` (single probe, or a chain walk
        # when enabled). Updates the hash table. Returns
        # [distance, length] or nil.
        #
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        def find_best_match(src, ip, ms, min_match, limit, ldm = nil,
                            max_distance = BLOCK_MAX_SIZE)
          size = src.bytesize
          return nil if ip + MIN_MATCH > size

          h = hash4(src, ip, ms.hash_log)
          candidate = ms.hash_table[h]
          if ms.max_chain.positive? && !ms.chain.empty? && (ip < ms.chain.length)
            ms.chain[ip] = candidate
          end
          ms.hash_table[h] = ip

          max_extend = limit + MIN_MATCH_ECONOMICAL - ip
          best_len = 0
          best_dist = 0
          walks = [ms.max_chain, 1].max

          walks.times do
            break if candidate.zero? || candidate >= ip

            dist = ip - candidate
            break if dist >= max_distance
            break if candidate + MIN_MATCH > size

            if read4(src, ip) == read4(src, candidate)
              m_len = MIN_MATCH + count_match(src, ip + MIN_MATCH,
                                              src, candidate + MIN_MATCH,
                                              [max_extend - MIN_MATCH, 0].max)
              if m_len > best_len
                best_len = m_len
                best_dist = dist
                break if best_len >= max_extend
              end
            end

            break if ms.max_chain.zero? || ms.chain.empty? || candidate >= ms.chain.length

            candidate = ms.chain[candidate]
          end

          if ldm
            lm = ldm.find_match(src, ip, max_distance, min_match,
                                limit + min_match)
            if lm && lm[1] > best_len
              best_len = lm[1]
              best_dist = lm[0]
            end
          end

          return nil if best_len < min_match

          [best_dist, best_len]
        end
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity

        # Read-only probe at `ip` without updating the hash table
        # (used by the lazy look-ahead so deferred positions do not
        # pollute the table early).
        #
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        def probe_match(src, ip, ms, min_match, limit, ldm = nil,
                        max_distance = BLOCK_MAX_SIZE)
          size = src.bytesize
          return nil if ip + MIN_MATCH > size

          candidate = ms.hash_table[hash4(src, ip, ms.hash_log)]

          best_len = 0
          best_dist = 0
          if candidate.positive? && candidate < ip
            dist = ip - candidate
            if dist < max_distance && candidate + MIN_MATCH <= size &&
                read4(src, ip) == read4(src, candidate)
              best_len = MIN_MATCH + count_match(
                src, ip + MIN_MATCH, src, candidate + MIN_MATCH,
                [limit + MIN_MATCH_ECONOMICAL - ip - MIN_MATCH, 0].max
              )
              best_dist = dist
            end
          end

          if ldm
            lm = ldm.find_match(src, ip, max_distance, min_match,
                                limit + min_match)
            if lm && lm[1] > best_len
              best_len = lm[1]
              best_dist = lm[0]
            end
          end

          return nil if best_len < min_match

          [best_dist, best_len]
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity

        # Insert hash entries for the start and the second-to-last
        # position of an emitted match (C ZSTD_insertAndFindFirstIndex
        # lazy-insert subset).
        #
        # rubocop:disable-next Metrics/AbcSize
        def insert_range(ms, src, start, len)
          size = src.bytesize
          if start + MIN_MATCH <= size
            h = hash4(src, start, ms.hash_log)
            ms.chain[start] = ms.hash_table[h] if start < ms.chain.length
            ms.hash_table[h] = start
          end
          pos = start + len - 2
          if pos.positive? && pos + MIN_MATCH <= size
            h = hash4(src, pos, ms.hash_log)
            ms.chain[pos] = ms.hash_table[h] if pos < ms.chain.length
            ms.hash_table[h] = pos
          end
        end

        # Rotate the finder-side repeat offsets (C ZSTD_updateRep).
        #
        # rubocop:disable-next Metrics/AbcSize
        def rotate_reps(reps, new_offset)
          if reps[0] == new_offset
            nil # already most recent
          elsif reps[1] == new_offset
            reps[0], reps[1] = reps[1], reps[0]
          elsif reps[2] == new_offset
            reps[2] = reps[1]
            reps[1] = reps[0]
            reps[0] = new_offset
          else
            reps[2] = reps[1]
            reps[1] = reps[0]
            reps[0] = new_offset
          end
        end
      end
    end
  end
end
