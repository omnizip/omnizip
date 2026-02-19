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
require_relative "restoration_method"

module Omnizip
  module Algorithms
    class PPMd8 < PPMdBase
      # PPMd8 prediction model with enhanced features
      #
      # Extends the basic PPMd model with:
      # - Restoration methods (RESTART/CUT_OFF)
      # - Run-length encoding for repetitions
      # - Enhanced update algorithms
      # - Glue count tracking for memory management
      class Model
        include PPMdBase::BaseConstants
        include Constants

        attr_reader :max_order, :root_context, :current_context,
                    :restoration_method, :run_length, :glue_count
        attr_accessor :order_fall, :prev_success

        # Initialize the PPMd8 model
        #
        # @param max_order [Integer] Maximum context order (2-16)
        # @param mem_size [Integer] Memory size for context allocation
        # @param restore_method [Integer] Restoration method type
        def initialize(
          max_order = DEFAULT_ORDER,
          mem_size = DEFAULT_MEM_SIZE,
          restore_method = DEFAULT_RESTORE_METHOD
        )
          validate_parameters(max_order, mem_size)

          @max_order = max_order
          @mem_size = mem_size
          @restoration_method = RestorationMethod.new(restore_method)

          # PPMd8-specific state
          @run_length = 0
          @init_rl = 0
          @glue_count = 0
          @order_fall = max_order
          @prev_success = 0

          # Initialize context tree
          @root_context = Context.new(-1, nil)
          @current_context = @root_context
          @context_history = []

          initialize_root_context
        end

        # Get probability information for a symbol
        #
        # @param symbol [Integer, nil] Symbol to encode (nil for decode)
        # @return [Hash] Probability information
        def get_symbol_probability(symbol = nil)
          context = find_context_with_symbol(symbol)

          if context && (state = context.find_symbol(symbol))
            build_symbol_probability(context, state, symbol)
          else
            build_escape_probability(context || @root_context)
          end
        end

        # Update model after encoding/decoding a symbol
        #
        # PPMd8 uses more sophisticated update algorithms
        #
        # @param symbol [Integer] The symbol that was encoded/decoded
        # @return [void]
        def update(symbol)
          update_run_length(symbol)
          update_context_statistics(symbol)
          update_current_context(symbol)
          check_memory_restoration
        end

        # Reset model to initial state
        #
        # @return [void]
        def reset
          @root_context = Context.new(-1, nil)
          @current_context = @root_context
          @context_history.clear
          @run_length = 0
          @glue_count = 0
          @order_fall = @max_order
          @prev_success = 0
          initialize_root_context
        end

        # Cut off old contexts to free memory (CUT_OFF restoration)
        #
        # @return [void]
        def cut_off_old_contexts
          # Simplified implementation - would traverse and prune
          # contexts based on usage statistics
          @glue_count = 0
        end

        private

        # Validate initialization parameters
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

        # Initialize root context
        def initialize_root_context
          ALPHABET_SIZE.times do |symbol|
            @root_context.add_symbol(symbol, 1)
          end
        end

        # Build probability hash for found symbol
        def build_symbol_probability(context, state, symbol)
          cum_freq = cumulative_frequency(context, symbol)
          {
            context: context,
            cumulative_freq: cum_freq,
            freq: state.freq,
            total_freq: context.total_freq,
            escape: false,
          }
        end

        # Build probability hash for escape
        def build_escape_probability(context)
          cum_freq = escape_cumulative_frequency(context)
          {
            context: context,
            cumulative_freq: cum_freq,
            freq: context.escape_freq,
            total_freq: context.total_freq,
            escape: true,
          }
        end

        # Update run-length counter (PPMd8 feature)
        def update_run_length(_symbol)
          if @run_length.positive?
            @run_length += 1
          else
            @run_length = 1
          end
        end

        # Update context statistics
        def update_context_statistics(symbol)
          if @current_context.find_symbol(symbol)
            @current_context.update_symbol(symbol)
          else
            @current_context.add_symbol(symbol)
          end
        end

        # Check if memory restoration is needed
        def check_memory_restoration
          return unless @root_context.needs_restoration?

          @restoration_method.restore(self)
        end

        # Find context containing symbol
        def find_context_with_symbol(symbol)
          return nil if symbol.nil?

          context = @current_context
          while context
            return context if context.find_symbol(symbol)

            context = context.suffix
          end

          nil
        end

        # Calculate cumulative frequency
        def cumulative_frequency(context, symbol)
          cum_freq = 0
          context.states.each do |sym, state|
            break if sym >= symbol

            cum_freq += state.freq
          end
          cum_freq
        end

        # Calculate escape cumulative frequency
        def escape_cumulative_frequency(context)
          context.sum_freq
        end

        # Update current context
        def update_current_context(symbol)
          @context_history.push(symbol)
          @context_history.shift if @context_history.size > @max_order
          @current_context = find_or_create_context(@context_history)
        end

        # Find or create context
        def find_or_create_context(sequence)
          return @root_context if sequence.empty?

          context = @root_context
          sequence.each_with_index do |_symbol, index|
            suffix = index.zero? ? @root_context : context
            context = Context.new(index, suffix)
          end

          context
        end
      end
    end
  end
end
