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
      # Sequences section decoder (RFC 8878 §3.1.1.3.2) and the LZ77
      # executor (§3.1.2).
      #
      # Decoding follows the C reference ZSTD_decodeSequence:
      #
      # - State initialization order: LL, OF, ML.
      # - Per sequence: resolve the offset first (reading its extra
      #   bits and updating the repeat-offset slots), then read the ML
      #   extra bits, then the LL extra bits.
      # - State updates (non-last sequences) in order LL, ML, OF.
      class SequencesDecoder
        include Constants

        Sequence = Struct.new(:literal_length, :match_length, :offset)

        # @return [Array<Sequence>]
        attr_reader :sequences

        # @return [Hash] FSE tables for the next block's Repeat mode
        attr_reader :fse_tables

        # Decode the sequences section at the head of `input`.
        #
        # @param input [String]
        # @param previous_tables [Hash] tables carried from the previous
        #   compressed block (:ll, :ml, :of entries)
        # @param executor [SequenceExecutor] repeat-offset state,
        #   updated in place while decoding
        # @return [SequencesDecoder]
        def self.decode(input, previous_tables = {}, executor = nil)
          new(input, previous_tables, executor || SequenceExecutor.new).decode_section
        end

        def initialize(input, previous_tables, executor)
          @input = input
          @previous_tables = previous_tables
          @executor = executor
          @sequences = []
          @fse_tables = {}
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def decode_section
          num_sequences, offset = read_sequence_count
          return self if num_sequences.zero?

          if @input.bytesize <= offset
            raise Omnizip::DecompressionError,
                  "truncated sequences section: missing modes byte"
          end
          # rubocop:enable Metrics/AbcSize

          modes = @input.getbyte(offset)
          ll_mode = (modes >> 6) & 0x03
          of_mode = (modes >> 4) & 0x03
          ml_mode = (modes >> 2) & 0x03

          cursor = offset + 1
          @ll_table, cursor = build_table(ll_mode, :ll,
                                          PREDEFINED_LL_DISTRIBUTION,
                                          LITERALS_LENGTH_ACCURACY_LOG, cursor)
          @of_table, cursor = build_table(of_mode, :of,
                                          PREDEFINED_OFFSET_DISTRIBUTION,
                                          OFFSET_ACCURACY_LOG, cursor)
          @ml_table, cursor = build_table(ml_mode, :ml,
                                          PREDEFINED_ML_DISTRIBUTION,
                                          MATCH_LENGTH_ACCURACY_LOG, cursor)

          decode_sequences(num_sequences, @input.byteslice(cursor..))
          self
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        private

        # Sequence count: 1-3 bytes (RFC 8878 §3.1.1.3.2.1).
        # rubocop:disable Metrics/AbcSize
        def read_sequence_count
          b0 = @input.getbyte(0)
          if b0 < 0x80
            [b0, 1]
          elsif b0 == 0xFF
            if @input.bytesize < 3
              raise Omnizip::DecompressionError,
                    "truncated 3-byte sequence count"
            end
            # rubocop:enable Metrics/AbcSize

            [@input.byteslice(1, 2).unpack1("v") + 0x7F00, 3]
          else
            if @input.bytesize < 2
              raise Omnizip::DecompressionError,
                    "truncated 2-byte sequence count"
            end

            [((b0 - 0x80) << 8) + @input.getbyte(1), 2]
          end
        end

        # Build the table for one symbol type. Returns [table, new_cursor].
        # rubocop:disable Metrics/AbcSize
        def build_table(mode, type, predef_distribution, predef_log, cursor)
          table = case mode
                  when MODE_PREDEFINED
                    FSE::Table.build_predefined(predef_distribution.to_a,
                                                predef_log)
                  when MODE_RLE
                    if cursor >= @input.bytesize
                      raise Omnizip::DecompressionError,
                            "RLE mode: missing symbol byte"
                    end
                    # rubocop:enable Metrics/AbcSize

                    symbol = @input.getbyte(cursor)
                    limit = { ll: LITERAL_LENGTH_TABLE.length,
                              ml: MATCH_LENGTH_TABLE.length,
                              of: OF_BASE.length }[type]
                    if symbol >= limit
                      raise Omnizip::DecompressionError,
                            "RLE symbol #{symbol} out of range for #{type}"
                    end

                    FSE::Table.build_rle(symbol, 0)
                  when MODE_FSE
                    tbl, consumed = FSE.read_table(@input.byteslice(cursor..))
                    attach_code_values(tbl, type)
                    @fse_tables[type] = tbl
                    return [tbl, cursor + consumed]
                  when MODE_REPEAT
                    prev = @previous_tables[type]
                    if prev.nil?
                      raise Omnizip::DecompressionError,
                            "repeat mode for #{type} without a previous table"
                    end

                    return [prev, cursor]
                  else
                    raise Omnizip::DecompressionError,
                          "invalid sequence mode #{mode}"
                  end

          attach_code_values(table, type)
          @fse_tables[type] = table
          cursor2 = mode == MODE_RLE ? cursor + 1 : cursor
          [table, cursor2]
        end

        # Annotate each FSE state with the (base, extra_bits) of the LL /
        # ML / OF code its symbol maps to, following the C reference's
        # precomputed seqSymbol layout.
        # rubocop:disable Metrics/AbcSize
        def attach_code_values(table, type)
          case type
          when :ll
            table.states.each do |st|
              base, bits = LITERAL_LENGTH_TABLE[st.symbol] || [0, 0]
              st.base_val = base
              st.nb_add_bits = bits
            end
            # rubocop:enable Metrics/AbcSize
          when :ml
            table.states.each do |st|
              base, bits = MATCH_LENGTH_TABLE[st.symbol] || [0, 0]
              st.base_val = base
              st.nb_add_bits = bits
            end
          when :of
            table.states.each do |st|
              st.base_val = OF_BASE[st.symbol] || 0
              st.nb_add_bits = OF_BITS[st.symbol] || 0
            end
          end
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def decode_sequences(count, bitstream_bytes)
          bs = FSE::BitStream.new(bitstream_bytes)

          ll_tbl = @ll_table
          of_tbl = @of_table
          ml_tbl = @ml_table
          ll_state = bs.read_bits(ll_tbl.accuracy_log)
          bs.reload
          of_state = bs.read_bits(of_tbl.accuracy_log)
          bs.reload
          ml_state = bs.read_bits(ml_tbl.accuracy_log)
          bs.reload

          count.times do |seq_idx|
            is_last = seq_idx == count - 1

            ll_e = ll_tbl[ll_state]
            of_e = of_tbl[of_state]
            ml_e = ml_tbl[ml_state]

            ll0 = ll_e.base_val.zero?
            offset = @executor.resolve_offset(of_e, ll0, bs)
            match_length = ml_e.base_val + bs.read_bits(ml_e.nb_add_bits)
            literal_length = ll_e.base_val + bs.read_bits(ll_e.nb_add_bits)

            unless is_last
              ll_state = ll_e.baseline + bs.read_bits(ll_e.num_bits)
              ml_state = ml_e.baseline + bs.read_bits(ml_e.num_bits)
              of_state = of_e.baseline + bs.read_bits(of_e.num_bits)
              bs.reload
            end
            # rubocop:enable Metrics/AbcSize

            @sequences << Sequence.new(literal_length, match_length, offset)
          end
        end
        # rubocop:enable Metrics/MethodLength
      end

      # Stateful LZ77 sequence executor (RFC 8878 §3.1.2). Tracks the
      # three repeat-offset slots across the frame; the slots are
      # updated while decoding each sequence's offset.
      class SequenceExecutor
        include Constants

        # @return [Array<Integer>] repeat offsets, most recent first
        attr_reader :repeat_offsets

        def initialize
          @repeat_offsets = DEFAULT_REPEAT_OFFSETS.dup
        end

        # Reset to the frame defaults [1, 4, 8].
        def reset
          @repeat_offsets = DEFAULT_REPEAT_OFFSETS.dup
        end

        # Resolve a sequence offset (C reference semantics).
        #
        # Offset codes 0 and 1 address the repeat slots; the exact
        # behaviour depends on ll0 (whether the sequence emits no
        # literals). Codes >= 2 carry a real distance:
        # distance = OF_BASE[code] + read(code bits).
        #
        # @param of_e [FSE::State] offset table entry for this sequence
        # @param ll0 [Boolean] literal length is zero
        # @param bs [FSE::BitStream]
        # @return [Integer] resolved byte distance
        # rubocop:disable Metrics/AbcSize
        def resolve_offset(of_e, ll0, bs)
          of_bits = of_e.nb_add_bits
          prev = @repeat_offsets

          if of_bits > 1
            offset = of_e.base_val + bs.read_bits(of_bits)
            prev[2] = prev[1]
            prev[1] = prev[0]
            prev[0] = offset
            offset
          elsif of_bits.zero?
            offset = prev[ll0 ? 1 : 0]
            if ll0
              prev[1] = prev[0]
              prev[0] = offset
            end
            # rubocop:enable Metrics/AbcSize
            offset
          else
            # of_bits == 1: the "rep3-1" special family.
            selector = of_e.base_val + (ll0 ? 1 : 0) + bs.read_bits(1)
            temp = case selector
                   when 1 then prev[1]
                   when 3 then prev[0] - 1
                   else prev[2]
                   end
            if temp.zero?
              raise Omnizip::DecompressionError,
                    "repeat offset 1 - 1 evaluated to 0 (corrupt stream)"
            end

            prev[2] = prev[1] unless selector == 1
            prev[1] = prev[0]
            prev[0] = temp
            temp
          end
        end

        # Execute decoded sequences against the literal buffer,
        # appending to output and returning the produced bytes.
        #
        # @param literals [String]
        # @param sequences [Array<SequencesDecoder::Sequence>]
        # @param output [String] accumulator (frame output so far)
        # @return [String] the block's output
        # rubocop:disable Metrics/AbcSize
        def execute(literals, sequences, output)
          lit_pos = 0
          block_start = output.bytesize

          sequences.each do |seq|
            ll = seq.literal_length
            if ll.positive?
              take = [ll, literals.bytesize - lit_pos].min
              output << literals.byteslice(lit_pos, take)
              lit_pos += take
            end
            # rubocop:enable Metrics/AbcSize

            distance = seq.offset
            if distance.zero? || distance > output.bytesize
              raise Omnizip::DecompressionError,
                    "match distance #{distance} exceeds decoded output " \
                    "length #{output.bytesize}"
            end

            ml = seq.match_length
            src_start = output.bytesize - distance
            ml.times { |i| output << output.getbyte(src_start + (i % distance)) }
          end

          output << literals.byteslice(lit_pos..) if lit_pos < literals.bytesize
          output.byteslice(block_start..)
        end
      end
    end
  end
end
