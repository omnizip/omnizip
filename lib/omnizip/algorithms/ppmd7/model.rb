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
require_relative "context"

module Omnizip
  module Algorithms
    class PPMd7 < Algorithm
      # Core PPMd7 prediction model
      #
      # The model maintains a tree of contexts, where each context
      # represents a sequence of symbols that have appeared in the
      # input. The model predicts the next symbol based on the
      # current context's statistics.
      #
      # The model uses Prediction by Partial Matching (PPM), which
      # tries progressively shorter contexts until it finds one
      # that has seen the current symbol before.
      class Model
        include Constants

        attr_reader :max_order, :root_context, :current_context

        # Initialize the PPMd7 model
        #
        # @param max_order [Integer] Maximum context order (2-16)
        # @param mem_size [Integer] Memory size for context allocation
        def initialize(max_order = DEFAULT_ORDER, mem_size = DEFAULT_MEM_SIZE)
          validate_parameters(max_order, mem_size)

          @max_order = max_order
          @mem_size = mem_size

          # Initialize context tree with root (order -1)
          @root_context = Context.new(-1, nil)
          @current_context = @root_context

          # Context history for maintaining context chain
          @context_history = []

          # Initialize root context with uniform distribution
          initialize_root_context
        end

        # Get probability information for encoding/decoding a symbol
        #
        # Returns information needed by range coder:
        # - cumulative frequency up to symbol
        # - symbol frequency
        # - total frequency
        # - whether this is an escape
        #
        # @param symbol [Integer, nil] Symbol to encode (nil for decode)
        # @return [Hash] Probability information
        def get_symbol_probability(symbol = nil)
          context = find_context_with_symbol(symbol)

          if context && (state = context.find_symbol(symbol))
            # Symbol found in context
            cum_freq = cumulative_frequency(context, symbol)
            {
              context: context,
              cumulative_freq: cum_freq,
              freq: state.freq,
              total_freq: context.total_freq,
              escape: false,
            }
          else
            # Use escape symbol
            cum_freq = escape_cumulative_frequency(context || @root_context)
            {
              context: context || @root_context,
              cumulative_freq: cum_freq,
              freq: (context || @root_context).escape_freq,
              total_freq: (context || @root_context).total_freq,
              escape: true,
            }
          end
        end

        # Update model after encoding/decoding a symbol
        #
        # This updates context statistics and creates new contexts
        # as needed.
        #
        # @param symbol [Integer] The symbol that was encoded/decoded
        # @return [void]
        def update(symbol)
          # Update current context or create new symbol
          if @current_context.find_symbol(symbol)
            @current_context.update_symbol(symbol)
          else
            @current_context.add_symbol(symbol)
          end

          # Move to next context
          update_current_context(symbol)
        end

        # Reset model to initial state
        #
        # @return [void]
        def reset
          @root_context = Context.new(-1, nil)
          @current_context = @root_context
          @context_history.clear
          initialize_root_context
        end

        private

        # Validate initialization parameters
        #
        # @param max_order [Integer] Maximum context order
        # @param mem_size [Integer] Memory size
        # @return [void]
        # @raise [ArgumentError] If parameters are invalid
        def validate_parameters(max_order, mem_size)
          unless max_order.between?(MIN_ORDER, MAX_ORDER)
            raise ArgumentError,
                  "max_order must be between #{MIN_ORDER} and #{MAX_ORDER}"
          end

          return if mem_size.between?(MIN_MEM_SIZE, MAX_MEM_SIZE)

          raise ArgumentError,
                "mem_size must be between #{MIN_MEM_SIZE} and " \
                "#{MAX_MEM_SIZE}"
        end

        # Initialize root context with all possible symbols
        #
        # The root context (order -1) contains all 256 possible
        # byte values with equal frequency. This ensures we can
        # always encode any symbol.
        #
        # @return [void]
        def initialize_root_context
          ALPHABET_SIZE.times do |symbol|
            @root_context.add_symbol(symbol, 1)
          end
        end

        # Find context that contains the given symbol
        #
        # Searches from current context up through suffixes until
        # finding one that has seen this symbol, or reaching root.
        #
        # @param symbol [Integer, nil] Symbol to find
        # @return [Context, nil] Context containing symbol or nil
        def find_context_with_symbol(symbol)
          return nil if symbol.nil?

          context = @current_context
          while context
            return context if context.find_symbol(symbol)

            context = context.suffix
          end

          nil
        end

        # Calculate cumulative frequency up to (but not including) symbol
        #
        # @param context [Context] The context
        # @param symbol [Integer] The symbol
        # @return [Integer] Cumulative frequency
        def cumulative_frequency(context, symbol)
          cum_freq = 0
          context.states.each do |sym, state|
            break if sym >= symbol

            cum_freq += state.freq
          end
          cum_freq
        end

        # Calculate cumulative frequency for escape symbol
        #
        # The escape symbol comes after all regular symbols in the
        # frequency range.
        #
        # @param context [Context] The context
        # @return [Integer] Cumulative frequency for escape
        def escape_cumulative_frequency(context)
          context.sum_freq
        end

        # Update current context after processing a symbol
        #
        # This maintains the context chain, creating new contexts
        # as needed to extend the order.
        #
        # @param symbol [Integer] Symbol that was processed
        # @return [void]
        def update_current_context(symbol)
          # Add to context history
          @context_history.push(symbol)

          # Limit history to max order
          @context_history.shift if @context_history.size > @max_order

          # Find or create context for new history
          @current_context = find_or_create_context(@context_history)
        end

        # Find or create a context for the given symbol sequence
        #
        # @param sequence [Array<Integer>] Sequence of symbols
        # @return [Context] The context for this sequence
        def find_or_create_context(sequence)
          return @root_context if sequence.empty?

          # Start from root and build up context chain
          context = @root_context
          sequence.each_with_index do |_symbol, index|
            suffix = index.zero? ? @root_context : context
            order = index
            context = Context.new(order, suffix)
          end

          context
        end
      end
    end
  end
end
