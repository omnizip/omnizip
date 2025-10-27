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
    class LZMA < Algorithm
      # LZMA State Machine for managing compression states
      #
      # This class implements the state machine used by LZMA to track
      # the current compression context. The state determines which
      # probability models are used for encoding the next symbol.
      #
      # LZMA uses 12 states that transition based on the type of
      # symbol being encoded (literal, match, rep match, etc.).
      # The state affects probability model selection for better
      # compression.
      class State
        # Total number of LZMA states
        NUM_STATES = 12

        # State transition tables
        # After encoding a literal
        LIT_STATES = [0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 4, 5].freeze

        # After encoding a match
        MATCH_STATES = [7, 7, 7, 7, 7, 7, 7, 10, 10, 10, 10, 10].freeze

        # After encoding a rep match
        REP_STATES = [8, 8, 8, 8, 8, 8, 8, 11, 11, 11, 11, 11].freeze

        # After encoding a short rep
        SHORT_REP_STATES = [9, 9, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11].freeze

        attr_reader :index

        # Initialize the state machine
        #
        # @param initial_state [Integer] Initial state index (default: 0)
        def initialize(initial_state = 0)
          @index = initial_state
        end

        # Update state after encoding a literal
        #
        # @return [void]
        def update_literal
          @index = LIT_STATES[@index]
        end

        # Update state after encoding a match
        #
        # @return [void]
        def update_match
          @index = MATCH_STATES[@index]
        end

        # Update state after encoding a repeat match
        #
        # @return [void]
        def update_rep
          @index = REP_STATES[@index]
        end

        # Update state after encoding a short repeat match
        #
        # @return [void]
        def update_short_rep
          @index = SHORT_REP_STATES[@index]
        end

        # Check if current state is a literal state
        #
        # @return [Boolean] True if state < 7
        def literal?
          @index < 7
        end

        # Check if current state is a match state
        #
        # @return [Boolean] True if state >= 7
        def match?
          @index >= 7
        end

        # Reset state to initial value
        #
        # @return [void]
        def reset
          @index = 0
        end

        # Create a copy of this state
        #
        # @return [State] A new State with the same index
        def dup
          State.new(@index)
        end

        # Get state index for probability model selection
        #
        # @return [Integer] Current state index
        def to_i
          @index
        end
      end
    end
  end
end
