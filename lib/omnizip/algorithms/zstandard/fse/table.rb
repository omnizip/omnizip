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

require_relative "bitstream"
require_relative "../constants"

module Omnizip
  module Algorithms
    class Zstandard
      module FSE
        # FSE state entry for decoding table
        #
        # Each entry contains:
        # - symbol: The symbol this state decodes to
        # - num_bits: Number of bits to read for next state
        # - baseline: Value to add to next state's value
        State = Struct.new(:symbol, :num_bits, :baseline)

        # FSE decoding table (RFC 8878 Section 4.1)
        #
        # Builds a decoding table from a probability distribution
        # according to RFC 8878.
        class Table
          include Constants

          # @return [Array<State>] Decoding table entries
          attr_reader :states

          # @return [Integer] Accuracy log (table size = 2^accuracy_log)
          attr_reader :accuracy_log

          # @return [Integer] Number of symbols in the table
          attr_reader :symbol_count

          # Build FSE table from normalized distribution
          #
          # @param distribution [Array<Integer>] Normalized symbol frequencies
          # @param accuracy_log [Integer] Log2 of table size
          # @return [Table] Built FSE table
          def self.build(distribution, accuracy_log)
            table_size = 1 << accuracy_log

            # Allocate cells using spread pattern
            cells = allocate_cells(distribution, table_size)

            # Calculate num_bits and baseline for each state
            states = calculate_state_values(cells, distribution, table_size)

            new(states, accuracy_log, distribution.length)
          end

          # Build from predefined distribution
          #
          # @param distribution [Array<Integer>] Predefined distribution
          # @param accuracy_log [Integer] Accuracy log
          # @return [Table]
          def self.build_predefined(distribution, accuracy_log)
            build(distribution, accuracy_log)
          end

          # Initialize with pre-built table
          #
          # @param states [Array<State>] Decoding states
          # @param accuracy_log [Integer]
          # @param symbol_count [Integer]
          def initialize(states, accuracy_log, symbol_count)
            @states = states
            @accuracy_log = accuracy_log
            @symbol_count = symbol_count
          end

          # Get state at index
          #
          # @param index [Integer] State index
          # @return [State] State at index
          def [](index)
            @states[index]
          end

          # Get table size
          #
          # @return [Integer] Number of entries in table
          def size
            @states.length
          end

          private

          # Allocate cells using FSE spread pattern
          #
          # The spread pattern distributes symbols across the table
          # using a step that ensures good distribution.
          def self.allocate_cells(distribution, table_size)
            cells = Array.new(table_size, nil)

            # Step = (table_size >> 1) + (table_size >> 3) + 3
            step = (table_size >> 1) + (table_size >> 3) + 3
            mask = table_size - 1

            position = 0

            distribution.each_with_index do |prob, symbol|
              next if prob.nil? || prob <= 0

              prob.times do
                # Find empty position
                while cells[position]
                  position = (position + step) & mask
                end

                cells[position] = symbol
                position = (position + step) & mask
              end
            end

            cells
          end

          # Calculate num_bits and baseline for each state
          def self.calculate_state_values(cells, distribution, table_size)
            states = Array.new(table_size)

            # Group positions by symbol
            symbol_positions = {}
            cells.each_with_index do |symbol, pos|
              next if symbol.nil?

              symbol_positions[symbol] ||= []
              symbol_positions[symbol] << pos
            end

            # Calculate state values for each symbol
            symbol_positions.each do |symbol, positions|
              prob = distribution[symbol]
              next if prob.nil? || prob <= 0

              positions.each_with_index do |pos, idx|
                # Calculate num_bits: -log2(prob/table_size)
                num_bits = calculate_num_bits(prob, table_size)

                # Calculate baseline
                baseline = idx

                states[pos] = State.new(symbol, num_bits, baseline)
              end
            end

            states
          end

          # Calculate number of bits needed for a symbol with given probability
          def self.calculate_num_bits(prob, table_size)
            return 0 if prob <= 0

            # num_bits = accuracy_log - log2(prob)
            # This is the number of extra bits needed
            log_prob = 0
            temp = prob
            while temp > 1
              log_prob += 1
              temp >>= 1
            end

            log_table = 0
            temp = table_size
            while temp > 1
              log_table += 1
              temp >>= 1
            end

            [0, log_table - log_prob].max
          end
        end

        # FSE Decoder (RFC 8878 Section 4.1)
        #
        # Decodes symbols from FSE-encoded bitstreams.
        class Decoder
          # @return [Table] FSE decoding table
          attr_reader :table

          # @return [Integer] Current state
          attr_reader :state

          # Initialize decoder with FSE table
          #
          # @param table [Table] FSE decoding table
          def initialize(table)
            @table = table
            @state = 0
          end

          # Initialize state from bitstream
          #
          # @param bitstream [BitStream] The bitstream to read from
          def init_state(bitstream)
            @state = bitstream.read_bits(@table.accuracy_log)
          end

          # Decode next symbol from bitstream
          #
          # @param bitstream [BitStream] The bitstream to read from
          # @return [Integer] Decoded symbol
          def decode(bitstream)
            entry = @table[@state]
            return 0 if entry.nil?

            symbol = entry.symbol

            # Read extra bits for next state
            if entry.num_bits > 0
              extra = bitstream.read_bits(entry.num_bits)
              @state = entry.baseline + extra
            else
              @state = entry.baseline
            end

            # Mask state to table size
            @state &= (@table.size - 1)

            symbol
          end

          # Decode multiple symbols
          #
          # @param bitstream [BitStream] The bitstream to read from
          # @param count [Integer] Number of symbols to decode
          # @return [Array<Integer>] Decoded symbols
          def decode_symbols(bitstream, count)
            symbols = []
            count.times do
              symbols << decode(bitstream)
            end
            symbols
          end
        end
      end
    end
  end
end
