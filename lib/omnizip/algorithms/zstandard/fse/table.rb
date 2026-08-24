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
      module FSE
        # One FSE table entry: the symbol decoded in this state and the
        # transition rule (bits to read, baseline to add). base_val /
        # nb_add_bits carry the sequence-code meaning of the symbol
        # (LL/ML baseline + extra bits, or OF base + offset code width)
        # and are attached by the sequences decoder.
        State = Struct.new(:symbol, :num_bits, :baseline, :base_val,
                           :nb_add_bits)

        # FSE decoding table built from a normalized distribution
        # (RFC 8878 §4.1, "From normalized distribution to decoding
        # tables"; mirrors the C reference FSE_buildDTable).
        class Table
          include Constants

          # @return [Array<State>]
          attr_reader :states

          # @return [Integer] log2 of the table size
          attr_reader :accuracy_log

          # @return [Integer] number of symbols in the source alphabet
          attr_reader :symbol_count

          # Build a table from a distribution.
          #
          # @param distribution [Array<Integer>] normalized counts;
          #   positive = cell count, -1 = "less than 1" low-probability
          #   symbol (one cell at the top of the table), 0 = absent
          # @param accuracy_log [Integer]
          # @return [Table]
          def self.build(distribution, accuracy_log)
            table_size = 1 << accuracy_log
            step = (table_size >> 1) + (table_size >> 3) + 3
            mask = table_size - 1

            # Phase 1a: low-probability (-1) symbols occupy single cells
            # from the top of the table downward.
            table_symbol = Array.new(table_size, 0xFFFF)
            high_threshold = table_size - 1
            distribution.each_with_index do |freq, symbol|
              next unless freq == -1

              table_symbol[high_threshold] = symbol
              if high_threshold.zero?
                raise Omnizip::DecompressionError,
                      "FSE table overflow placing low-probability symbol"
              end

              high_threshold -= 1
            end

            # Phase 1b: spread positive-count symbols from position 0,
            # skipping the reserved low-probability area.
            position = 0
            distribution.each_with_index do |freq, symbol|
              next unless freq.positive?

              freq.times do
                table_symbol[position] = symbol
                position = (position + step) & mask
                position = (position + step) & mask while position > high_threshold
              end
            end

            # Phase 2: symbolNext starts at 1 for -1/1 counts, at the
            # count itself otherwise.
            symbol_next = Array.new(distribution.length, 0)
            singular = [-1, 1].freeze
            distribution.each_with_index do |freq, symbol|
              next if freq.zero?

              symbol_next[symbol] = singular.include?(freq) ? 1 : freq
            end

            # Phase 3: per-cell transition rules.
            states = table_symbol.map do |symbol|
              next_state = symbol_next[symbol]
              symbol_next[symbol] += 1
              nb_bits = accuracy_log - Constants.highbit32(next_state)
              baseline = (next_state << nb_bits) - table_size
              State.new(symbol, nb_bits, baseline)
            end

            new(states, accuracy_log, distribution.length)
          end

          # Build from an RFC 8878 §4.1.3 predefined distribution.
          #
          # @param distribution [Array<Integer>]
          # @param accuracy_log [Integer]
          # @return [Table]
          def self.build_predefined(distribution, accuracy_log)
            build(distribution, accuracy_log)
          end

          # Single-symbol RLE table: every state decodes `symbol` with a
          # full state reset.
          #
          # @return [Table]
          def self.build_rle(symbol, accuracy_log)
            new(Array.new(1 << accuracy_log) { State.new(symbol, 0, 0) },
                accuracy_log, 1)
          end

          def initialize(states, accuracy_log, symbol_count)
            @states = states
            @accuracy_log = accuracy_log
            @symbol_count = symbol_count
          end

          # @return [State]
          def [](index)
            @states[index]
          end

          # @return [Integer]
          def size
            @states.length
          end
        end

        # Stateful single-stream FSE decoder.
        class Decoder
          # @return [Integer] current state index
          attr_reader :state

          # @param table [Table]
          def initialize(table)
            @table = table
            @state = 0
          end

          # Initialize the state by reading accuracy_log bits.
          def init_state(bitstream)
            @state = bitstream.read_bits(@table.accuracy_log)
          end

          # Decode one symbol: read it from the current state, then
          # transition.
          #
          # @return [Integer] symbol
          def decode(bitstream)
            entry = @table[@state]
            @state = if entry.num_bits.positive?
                       entry.baseline + bitstream.read_bits(entry.num_bits)
                     else
                       entry.baseline
                     end
            entry.symbol
          end

          # The symbol the current state decodes, without transitioning.
          #
          # @return [Integer]
          def current_symbol
            @table[@state].symbol
          end
        end
      end
    end
  end
end
