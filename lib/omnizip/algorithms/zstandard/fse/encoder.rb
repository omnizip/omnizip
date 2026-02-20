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

require_relative "../constants"
require_relative "bitstream"

module Omnizip
  module Algorithms
    class Zstandard
      module FSE
        # FSE Encoder (RFC 8878 Section 4.1)
        #
        # Encodes symbols using Finite State Entropy coding.
        # FSE is a variant of arithmetic coding that uses table-based state transitions.
        class Encoder
          include Constants

          # @return [Array<Integer>] Symbol distribution (normalized frequencies)
          attr_reader :distribution

          # @return [Integer] Accuracy log (table size = 2^accuracy_log)
          attr_reader :accuracy_log

          # @return [Integer] Table size
          attr_reader :table_size

          # Build FSE encoder from symbol frequencies
          #
          # @param frequencies [Array<Integer>] Raw symbol frequencies
          # @param max_accuracy_log [Integer] Maximum accuracy log (default 9)
          # @return [Encoder] FSE encoder
          def self.build_from_frequencies(frequencies,
max_accuracy_log = FSE_MAX_ACCURACY_LOG)
            return nil if frequencies.nil? || frequencies.empty?

            # Normalize frequencies to table size
            distribution, accuracy_log = normalize_distribution(frequencies,
                                                                max_accuracy_log)

            new(distribution, accuracy_log)
          end

          # Normalize frequency distribution
          #
          # Converts raw frequencies to normalized distribution that sums to 2^accuracy_log.
          #
          # @param frequencies [Array<Integer>] Raw frequencies
          # @param max_accuracy_log [Integer] Maximum accuracy log
          # @return [Array<Array<Integer>, Integer>] Normalized distribution and accuracy log
          def self.normalize_distribution(frequencies, max_accuracy_log)
            # Count non-zero symbols
            total_freq = frequencies.sum
            return [[], 0] if total_freq.zero?

            # Find minimum accuracy log that fits the distribution
            num_symbols = frequencies.count { |f| f&.positive? }
            accuracy_log = [calculate_min_accuracy_log(num_symbols),
                            FSE_MIN_ACCURACY_LOG].max
            accuracy_log = [accuracy_log, max_accuracy_log].min

            table_size = 1 << accuracy_log

            # Normalize frequencies to table size
            distribution = normalize_frequencies(frequencies, table_size)

            # Verify distribution sums to table size
            sum = distribution.sum
            if sum != table_size
              # Adjust to make it sum correctly
              adjust_distribution(distribution, table_size - sum)
            end

            [distribution, accuracy_log]
          end

          # Calculate minimum accuracy log for given number of symbols
          def self.calculate_min_accuracy_log(num_symbols)
            return 0 if num_symbols <= 1

            log = 0
            temp = num_symbols - 1
            while temp.positive?
              log += 1
              temp >>= 1
            end
            log
          end

          # Normalize frequencies to fit table size
          def self.normalize_frequencies(frequencies, table_size)
            total = frequencies.sum
            return Array.new(frequencies.length, 0) if total.zero?

            # Scale frequencies
            frequencies.map do |freq|
              next 0 if freq.nil? || freq <= 0

              normalized = ((freq * table_size) + (total / 2)) / total
              [normalized, 1].max # Minimum 1 for non-zero symbols
            end
          end

          # Adjust distribution to sum to exactly table_size
          def self.adjust_distribution(distribution, delta)
            return if delta.zero?

            if delta.positive?
              # Need to add: increment largest probabilities
              delta.times do
                max_idx = distribution.each_with_index.max_by { |v, _| v }&.last
                distribution[max_idx] += 1 if max_idx
              end
            else
              # Need to subtract: decrement smallest non-zero probabilities
              (-delta).times do
                min_idx = distribution.each_with_index.select do |v, _|
                  v > 1
                end.min_by { |v, _| v }&.last
                distribution[min_idx] -= 1 if min_idx
              end
            end
          end

          # Initialize FSE encoder
          #
          # @param distribution [Array<Integer>] Normalized symbol distribution
          # @param accuracy_log [Integer] Accuracy log
          def initialize(distribution, accuracy_log)
            @distribution = distribution
            @accuracy_log = accuracy_log
            @table_size = 1 << accuracy_log

            # Build encoding tables
            build_encoding_tables
          end

          # Encode symbols to bitstream
          #
          # @param symbols [Array<Integer>] Symbols to encode
          # @return [String] Encoded bitstream
          def encode(symbols)
            return "" if symbols.nil? || symbols.empty?

            # Initialize state from last symbol (reverse order encoding)
            bitstream = []

            # Encode in reverse order
            state = @table_size - 1 # Initial state

            symbols.reverse_each.with_index do |symbol, _idx|
              entry = @symbol_to_state[symbol]
              next unless entry

              # Find state for this symbol
              state = find_state_for_symbol(symbol, state)

              # Output bits for state transition
              num_bits = entry[:num_bits]
              if num_bits.positive?
                # Write lower num_bits of state
                mask = (1 << num_bits) - 1
                bits_to_write = state & mask
                write_bits(bitstream, bits_to_write, num_bits)
                state >>= num_bits
              end
            end

            # Write final state
            write_bits(bitstream, state, @accuracy_log)

            # Convert bit array to bytes (in reverse for FSE)
            bits_to_bytes(bitstream.reverse)
          end

          # Get number of symbols in distribution
          #
          # @return [Integer]
          def symbol_count
            @distribution.length
          end

          private

          # Build encoding tables from distribution
          def build_encoding_tables
            @symbol_to_state = {}
            @state_to_symbol = Array.new(@table_size)

            # Allocate states to symbols based on distribution
            position = 0
            step = (@table_size >> 1) + (@table_size >> 3) + 3
            mask = @table_size - 1

            @distribution.each_with_index do |prob, symbol|
              next if prob.nil? || prob <= 0

              # Calculate number of bits for this symbol
              num_bits = [@accuracy_log - log2_int(prob), 0].max

              # Allocate states
              prob.times do
                # Find empty position using spread
                while @state_to_symbol[position]
                  position = (position + step) & mask
                end

                @state_to_symbol[position] = {
                  symbol: symbol,
                  num_bits: num_bits,
                  baseline: 0, # Will be calculated
                }

                position = (position + step) & mask
              end

              @symbol_to_state[symbol] = {
                num_bits: num_bits,
                baseline: 0,
              }
            end

            # Calculate baselines
            calculate_baselines
          end

          # Calculate baseline values for each state
          def calculate_baselines
            # Group states by symbol
            symbol_states = {}
            @state_to_symbol.each_with_index do |entry, state|
              next unless entry

              symbol = entry[:symbol]
              symbol_states[symbol] ||= []
              symbol_states[symbol] << { state: state, entry: entry }
            end

            # Sort states within each symbol and assign baselines
            symbol_states.each_value do |states|
              states.sort_by! { |s| s[:state] }
              states.each_with_index do |s, idx|
                s[:entry][:baseline] = idx
              end
            end
          end

          # Find state for encoding a symbol
          def find_state_for_symbol(symbol, current_state)
            entry = @symbol_to_state[symbol]
            return 0 unless entry

            # Find the appropriate state based on current state
            num_bits = entry[:num_bits]
            if num_bits.positive?
              # Use lower bits of current state to select state
              ((current_state & ((1 << num_bits) - 1)) << (@accuracy_log - num_bits)) |
                (entry[:baseline] >> num_bits)
            else
              entry[:baseline]
            end
          end

          # Write bits to bitstream array
          def write_bits(bitstream, value, count)
            count.times do |i|
              bitstream << ((value >> i) & 1)
            end
          end

          # Convert bit array to bytes
          def bits_to_bytes(bits)
            # Pad to byte boundary
            bits = bits.dup
            while bits.length % 8 != 0
              bits << 0
            end

            bytes = []
            bits.each_slice(8) do |byte_bits|
              byte = 0
              byte_bits.each_with_index do |bit, i|
                byte |= (bit << i)
              end
              bytes << byte
            end

            bytes.pack("C*")
          end

          # Integer log2
          def log2_int(value)
            return 0 if value <= 1

            log = 0
            temp = value
            while temp > 1
              log += 1
              temp >>= 1
            end
            log
          end
        end
      end
    end
  end
end
