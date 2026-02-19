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
  module Implementations
    module Base
      # Abstract base class for LZMA state machines.
      #
      # Both XZ Utils and 7-Zip use a 12-state finite state machine (FSM)
      # for tracking the encoding context. However, they have different
      # transition tables between states.
      #
      # The 12 states are:
      # - States 0-6: Literal mode (last symbol was a literal)
      # - States 7-9: Match mode (last symbol was a match)
      # - States 10-11: Short rep match mode (last symbol was a rep match of length 1)
      #
      # State transitions depend on whether the current symbol is:
      # - A literal (byte)
      # - A match (length + distance)
      # - A repeated match (using rep0-rep3)
      #
      # Subclasses must provide their specific transition table via
      # the {#update!} method.
      #
      # @abstract Subclasses must implement {#update!}
      class StateMachineBase
        # All valid LZMA states (0-11)
        STATES = (0..11)

        # States where literal encoding should use matched literal mode
        # (i.e., compare with match byte at rep0)
        LITERAL_MATCHED_STATES = [7, 8, 9, 10, 11].freeze

        attr_reader :state

        # Initialize the state machine.
        #
        # @param initial_state [Integer] Initial state value (default: 0)
        def initialize(initial_state = 0)
          unless STATES.include?(initial_state)
            raise ArgumentError,
                  "Invalid initial state: #{initial_state}, must be 0-11"
          end

          @state = initial_state
        end

        # Reset to initial state.
        #
        # @return [void]
        def reset!
          @state = 0
        end

        # Update state based on encoding decision.
        #
        # Both XZ Utils and 7-Zip use different transition tables.
        # Subclasses must implement this with their specific table.
        #
        # @param is_match [Boolean] true if last symbol was a match, false if literal
        # @param is_short_rep [Boolean] true if last symbol was a short rep (length=1)
        # @raise [NotImplementedError] Always raised in base class
        # @return [void]
        def update!(is_match, is_short_rep: false)
          raise NotImplementedError,
                "#{self.class} must implement #update!"
        end

        # Update state for literal encoding.
        #
        # This is a convenience method that calls {#update!} with is_match=false.
        #
        # @return [void]
        def update_literal!
          update!(false)
        end

        # Update state for match encoding.
        #
        # This is a convenience method that calls {#update!} with is_match=true.
        #
        # @return [void]
        def update_match!(_distance = nil)
          update!(true)
        end

        # Update state for short rep match (length=1).
        #
        # This is a convenience method that calls {#update!} with appropriate params.
        #
        # @return [void]
        def update_short_rep!
          update!(true, is_short_rep: true)
        end

        # Update state for long rep match (length>1).
        #
        # This is a convenience method that calls {#update!} with appropriate params.
        #
        # @return [void]
        def update_long_rep!
          update!(true, is_short_rep: false)
        end

        # Check if currently in literal mode.
        #
        # States 0-6 are considered "literal mode" where the last symbol
        # was a literal byte.
        #
        # @return [Boolean] true if in literal mode (states 0-6)
        def literal_mode?
          @state < 7
        end

        # Check if currently in match mode.
        #
        # States 7-11 are considered "match mode" where the last symbol
        # was a match of some kind.
        #
        # @return [Boolean] true if in match mode (states 7-11)
        def match_mode?
          @state >= 7
        end

        # Check if matched literal encoding should be used.
        #
        # In states 7-11, literal encoding should compare with the match byte
        # at rep0 for better compression.
        #
        # @return [Boolean] true if matched literal should be used
        def use_matched_literal?
          LITERAL_MATCHED_STATES.include?(@state)
        end

        # Get state as integer.
        #
        # This is used for probability model indexing.
        #
        # @return [Integer] Current state value (0-11)
        def value
          @state
        end

        # Set state directly.
        #
        # This is useful for initialization or testing.
        #
        # @param new_state [Integer] New state value (0-11)
        # @raise [ArgumentError] If state is invalid
        # @return [void]
        def state=(new_state)
          unless STATES.include?(new_state)
            raise ArgumentError,
                  "Invalid state: #{new_state}, must be 0-11"
          end

          @state = new_state
        end
      end
    end
  end
end
