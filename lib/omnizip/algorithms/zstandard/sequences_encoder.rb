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
      # Sequences section encoder (RFC 8878 §3.1.1.3.2; port of the
      # omnizip-rs encoder/sequences.rs, from zstd_compress_sequences.c).
      #
      # Encodes the match finder's sequences with three FSE states
      # (LL, OF, ML) into the reverse bitstream, choosing Predefined or
      # FSE_Compressed tables per symbol type. Repeat offsets use the
      # offBase 0/1/2 short codes exactly as the decoder resolves
      # them.
      module SequencesEncoder
        include Constants

        MODE_PREDEFINED = 0
        MODE_FSE = 2

        # Slack favoring Predefined tables (the payload estimate is
        # entropy-approximate; marginal FSE wins on small streams are
        # noise and lose in practice).
        FSE_SLACK_BITS = 24

        module_function

        # Encode the sequences section for `seq_store`.
        #
        # @param seq_store [MatchFinder::SeqStore]
        # @param initial_reps [Array<Integer>] wire repeat offsets the
        #   decoder holds before this block
        # @return [Array(String, Array<Integer>)] the section bytes and
        #   the wire rep state after this block
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def encode_section(seq_store, initial_reps)
          nb_seq = seq_store.sequences.length
          out = write_sequence_count(nb_seq)
          return [out, initial_reps] if nb_seq.zero?

          ll_codes, ml_codes, of_codes, ll_extras, ml_extras, off_bases,
            wire_reps = compute_codes(seq_store, initial_reps)

          ll_count = Array.new(LITERAL_LENGTH_TABLE.length, 0)
          ml_count = Array.new(MATCH_LENGTH_TABLE.length, 0)
          of_count = Array.new(32, 0)
          ll_max = count_symbols(ll_codes, ll_count)
          ml_max = count_symbols(ml_codes, ml_count)
          of_max = count_symbols(of_codes, of_count)

          ll_choice = choose_table_mode(ll_count, ll_max,
                                        PREDEFINED_LL_DISTRIBUTION, 6, 35, 9,
                                        nb_seq)
          of_choice = choose_table_mode(of_count, of_max,
                                        PREDEFINED_OFFSET_DISTRIBUTION, 5, 28,
                                        8, nb_seq)
          ml_choice = choose_table_mode(ml_count, ml_max,
                                        PREDEFINED_ML_DISTRIBUTION, 6, 52, 9,
                                        nb_seq)

          modes = (ll_choice[:mode] << 6) | (of_choice[:mode] << 4) |
            (ml_choice[:mode] << 2)
          out << modes.chr

          if ll_choice[:mode] == MODE_FSE
            out << FSE::Encoder.new(ll_choice[:norm], ll_choice[:table_log],
                                    ll_max).write_ncount
          end
          if of_choice[:mode] == MODE_FSE
            out << FSE::Encoder.new(of_choice[:norm], of_choice[:table_log],
                                    of_max).write_ncount
          end
          if ml_choice[:mode] == MODE_FSE
            out << FSE::Encoder.new(ml_choice[:norm], ml_choice[:table_log],
                                    ml_max).write_ncount
          end

          ll_ctable = table_for(ll_choice)
          of_ctable = table_for(of_choice)
          ml_ctable = table_for(ml_choice)

          out << encode_sequences_bitstream(
            ll_codes, ml_codes, of_codes, ll_extras, ml_extras, off_bases,
            ll_ctable, ml_ctable, of_ctable
          )

          [out, wire_reps]
        end
        # rubocop:enable Metrics/MethodLength

        # Compute per-sequence codes and extras, tracking the WIRE rep
        # state exactly as the decoder's resolve_offset does (this is
        # the state the next block must carry, not the match finder's).
        #
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def compute_codes(seq_store, initial_reps)
          ll_codes = []
          ml_codes = []
          of_codes = []
          ll_extras = []
          ml_extras = []
          off_bases = []
          reps = initial_reps.dup

          seq_store.sequences.each do |seq|
            ll_c, ll_e = ll_code(seq.literal_length)
            ml_c, ml_e = ml_code(seq.match_length)
            ll0 = seq.literal_length.zero?

            ob = if !ll0 && seq.offset == reps[0]
                   1 # rep1: decoder uses prev[0], no rotation
                 elsif ll0 && seq.offset == reps[1]
                   used = reps[1] # decoder swaps prev[0]/prev[1]
                   reps[1] = reps[0]
                   reps[0] = used
                   1
                 elsif seq.offset == reps[2] && seq.offset > 3
                   used = reps[2] # rep3: decoder shifts prev[2] to front
                   reps[2] = reps[1]
                   reps[1] = reps[0]
                   reps[0] = used
                   ll0 ? 2 : 3
                 else
                   reps[2] = reps[1]
                   reps[1] = reps[0]
                   reps[0] = seq.offset
                   seq.offset + 3
                 end

            ll_codes << ll_c
            ml_codes << ml_c
            of_codes << [ob.bit_length - 1, 31].min
            ll_extras << ll_e
            ml_extras << ml_e
            off_bases << ob
          end

          [ll_codes, ml_codes, of_codes, ll_extras, ml_extras, off_bases,
           reps]
        end
        # rubocop:enable Metrics/MethodLength

        # LL code for a literal length: (code, extra value).
        def ll_code(lit_len)
          code = LITERAL_LENGTH_TABLE.length - 1
          while code.positive? && LITERAL_LENGTH_TABLE[code][0] > lit_len
            code -= 1
          end
          [code, lit_len - LITERAL_LENGTH_TABLE[code][0]]
        end

        # ML code for a match length: (code, extra value).
        def ml_code(match_len)
          code = MATCH_LENGTH_TABLE.length - 1
          while code.positive? && MATCH_LENGTH_TABLE[code][0] > match_len
            code -= 1
          end
          [code, match_len - MATCH_LENGTH_TABLE[code][0]]
        end

        def count_symbols(codes, count)
          max_sym = 0
          codes.each do |c|
            count[c] += 1
            max_sym = c if c > max_sym
          end
          max_sym
        end

        # Choose Predefined vs FSE_Compressed for one symbol type.
        #
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def choose_table_mode(count, max_sym, default_norm, default_log,
                              default_max_sym, accuracy_cap, total)
          predefined_viable = (0..max_sym).all? do |s|
            count[s].zero? ||
              (s < default_norm.length && default_norm[s] != 0)
          end

          opt_log = FSE::Encoder.optimal_table_log(accuracy_cap, total,
                                                   max_sym)
          custom_norm = FSE::Encoder.normalize_count(
            opt_log, count, total, max_sym, use_low_prob: false
          )

          fse_norm = if custom_norm.empty?
                       single = Array.new(max_sym + 1, 0)
                       single[max_sym] = 1 << opt_log
                       single
                     else
                       custom_norm
                     end

          unless predefined_viable
            return { mode: MODE_FSE, norm: fse_norm, table_log: opt_log,
                     max_sym: max_sym }
          end

          predef_bits = estimate_cost(count, default_norm, default_log,
                                      max_sym)
          fse_bits = estimate_cost(count, fse_norm, opt_log, max_sym) +
            (8 * ncount_size(fse_norm, max_sym, opt_log))

          if fse_bits + FSE_SLACK_BITS < predef_bits
            { mode: MODE_FSE, norm: fse_norm, table_log: opt_log,
              max_sym: max_sym }
          else
            { mode: MODE_PREDEFINED, norm: default_norm.to_a,
              table_log: default_log, max_sym: default_max_sym }
          end
        end
        # rubocop:enable Metrics/MethodLength

        # Estimated payload cost in bits for a distribution.
        def estimate_cost(count, norm, table_log, max_sym)
          table_size = 1 << table_log
          total_bits = 0
          (0..max_sym).each do |s|
            next if count[s].zero?

            n = s < norm.length ? norm[s] : 0
            prob = if n.positive?
                     n
                   elsif n == -1
                     1
                   else
                     table_size
                   end
            total_bits += (count[s] * Math.log(table_size.to_f / prob, 2))
              .round
          end
          total_bits
        end

        def table_for(choice)
          FSE::Encoder.new(choice[:norm], choice[:table_log], choice[:max_sym])
        end

        # Exact size of the NCount header a distribution would write.
        def ncount_size(norm, max_sym, table_log)
          FSE::Encoder.new(norm, table_log, max_sym).write_ncount.bytesize
        rescue Omnizip::CompressionError
          Float::INFINITY
        end

        # Sequence count, 1-3 bytes (RFC 8878 §3.1.1.3.2.1).
        def write_sequence_count(nb_seq)
          if nb_seq < 128
            [nb_seq].pack("C")
          elsif nb_seq < 0x7F00
            [128 + (nb_seq >> 8), nb_seq & 0xFF].pack("CC")
          else
            v = nb_seq - 0x7F00
            [0xFF, v & 0xFF, (v >> 8) & 0xFF].pack("C*")
          end
        end

        # The reverse-order three-state FSE bitstream (port of the
        # Rust encode_sequences_bitstream). The decoder reads states
        # LL, OF, ML first and consumes extras OF, ML, LL per
        # sequence, so the encoder initializes from the LAST sequence
        # and walks backwards.
        #
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def encode_sequences_bitstream(ll_codes, ml_codes, of_codes,
                                       ll_extras, ml_extras, off_bases,
                                       ll_ctable, ml_ctable, of_ctable)
          nb_seq = ll_codes.length
          bitc = FSE::Encoder::BitCStream.new

          state_ml = FSE::Encoder::CState.init2(ml_ctable, ml_codes[nb_seq - 1])
          state_of = FSE::Encoder::CState.init2(of_ctable, of_codes[nb_seq - 1])
          state_ll = FSE::Encoder::CState.init2(ll_ctable, ll_codes[nb_seq - 1])

          last = nb_seq - 1
          bitc.add_bits(ll_extras[last],
                        LITERAL_LENGTH_TABLE[ll_codes[last]][1])
          bitc.flush
          bitc.add_bits(ml_extras[last],
                        MATCH_LENGTH_TABLE[ml_codes[last]][1])
          bitc.flush
          bitc.add_bits(off_bases[last], of_codes[last])
          bitc.flush

          (nb_seq - 2).downto(0) do |n|
            state_of.encode(bitc, of_ctable, of_codes[n])
            state_ml.encode(bitc, ml_ctable, ml_codes[n])
            bitc.flush
            state_ll.encode(bitc, ll_ctable, ll_codes[n])
            bitc.flush

            bitc.add_bits(ll_extras[n],
                          LITERAL_LENGTH_TABLE[ll_codes[n]][1])
            bitc.add_bits(ml_extras[n],
                          MATCH_LENGTH_TABLE[ml_codes[n]][1])
            bitc.flush
            bitc.add_bits(off_bases[n], of_codes[n])
            bitc.flush
          end

          state_ml.flush(bitc)
          state_of.flush(bitc)
          state_ll.flush(bitc)
          bitc.close
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
