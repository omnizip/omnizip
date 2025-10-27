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

require_relative "constants"
require_relative "symbol_state"

module Omnizip
  module Algorithms
    class PPMd7 < Algorithm
      # Represents a context node in the PPMd7 model
      #
      # A context in PPMd is a sequence of symbols that have appeared
      # previously. Each context tracks the symbols that have followed
      # it and their frequencies. This forms a tree structure where
      # each node represents a different context.
      #
      # The context uses symbol states to track:
      # - Which symbols have appeared after this context
      # - How frequently each symbol has appeared
      # - Escape probabilities for unknown symbols
      class Context
        include Constants

        attr_reader :order, :suffix, :states, :sum_freq
        attr_accessor :escape_freq

        # Initialize a new context
        #
        # @param order [Integer] The order of this context (depth in tree)
        # @param suffix [Context, nil] Parent context (shorter context)
        def initialize(order, suffix = nil)
          @order = order
          @suffix = suffix
          @states = {} # symbol => SymbolState
          @sum_freq = 0
          @escape_freq = INIT_ESCAPE_FREQ
        end

        # Find a symbol state in this context
        #
        # @param symbol [Integer] The symbol to find (0-255)
        # @return [SymbolState, nil] The state if found, nil otherwise
        def find_symbol(symbol)
          @states[symbol]
        end

        # Add a new symbol to this context
        #
        # This is called when a symbol appears for the first time
        # after this context.
        #
        # @param symbol [Integer] The symbol to add (0-255)
        # @param freq [Integer] Initial frequency (default: 1)
        # @return [SymbolState] The newly created state
        def add_symbol(symbol, freq = 1)
          raise ArgumentError, "Symbol already exists" if @states[symbol]

          state = SymbolState.new(symbol, freq)
          @states[symbol] = state
          @sum_freq += freq
          state
        end

        # Update symbol frequency after encoding/decoding
        #
        # Increases the frequency count for the symbol and updates
        # the total frequency sum for this context.
        #
        # @param symbol [Integer] The symbol to update
        # @param increment [Integer] Amount to increase frequency
        # @return [void]
        def update_symbol(symbol, increment = 1)
          state = @states[symbol]
          return unless state

          state.freq += increment
          @sum_freq += increment
          rescale_frequencies if @sum_freq > MAX_FREQ
        end

        # Get total frequency including escape
        #
        # @return [Integer] Total frequency for probability calculation
        def total_freq
          @sum_freq + @escape_freq
        end

        # Check if context needs escape (has unseen symbols)
        #
        # @return [Boolean] True if escape symbol is needed
        def needs_escape?
          @states.size < ALPHABET_SIZE
        end

        # Get all symbols in order of frequency
        #
        # @return [Array<Integer>] Symbols sorted by frequency (desc)
        def symbols_by_frequency
          @states.values.sort_by { |s| -s.freq }.map(&:symbol)
        end

        # Check if this is a root context
        #
        # @return [Boolean] True if this has no suffix (order 0)
        def root?
          @suffix.nil?
        end

        # Get the number of distinct symbols in this context
        #
        # @return [Integer] Number of symbols tracked
        def num_symbols
          @states.size
        end

        private

        # Rescale frequencies when they grow too large
        #
        # This prevents arithmetic overflow and maintains reasonable
        # probability distributions. Divides all frequencies by 2
        # while maintaining minimum frequency of 1.
        #
        # @return [void]
        def rescale_frequencies
          @sum_freq = 0
          @states.each_value do |state|
            state.freq = [(state.freq + 1) / 2, 1].max
            @sum_freq += state.freq
          end
        end
      end
    end
  end
end
