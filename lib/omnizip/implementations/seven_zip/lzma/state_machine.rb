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

require_relative "../../../algorithms/lzma/state"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # 7-Zip LZMA SDK state machine implementation.
        #
        # This is the original SdkStateMachine moved from algorithms/lzma/sdk_state_machine.rb
        # to the new namespace structure.
        #
        # Ported from 7-Zip LZMA SDK by Igor Pavlov.
        class StateMachine < Omnizip::Algorithms::LZMA::State
          # State categories (SDK classification)
          CATEGORY_LITERAL = :literal      # States 0-6
          CATEGORY_MATCH = :match          # States 7-9
          CATEGORY_REP = :rep              # State 8, 11
          CATEGORY_SHORT_REP = :short_rep  # State 9, 11 after short rep

          # Check if current state is a character state
          #
          # Character states (0-6) occur after literal encoding.
          # The SDK uses this to determine probability model selection.
          # This is SDK's IsCharState() macro.
          #
          # @return [Boolean] True if state < 7
          def is_char_state?
            @index < 7
          end

          # Get state value (alias for index)
          #
          # @return [Integer] Current state index
          def value
            @index
          end

          # Get literal state index for probability model selection
          #
          # The SDK uses a simplified state value for literal encoding:
          # - States 0-3 map to themselves (0-3)
          # - States 4-6 map to 4-6
          # - States 7+ map to state - 3 (4-9)
          #
          # This creates 10 possible literal contexts (0-9) from 12 states.
          # From LzmaEnc.c: litState = (state < 4) ? state : (state - (state < 10 ? 3 : 6))
          #
          # @return [Integer] Literal state index (0-9)
          def literal_state
            if @index < 4
              @index
            elsif @index < 10
              @index - 3
            else
              @index - 6
            end
          end

          # Check if matched literal mode should be used
          #
          # XZ Utils logic (lzma_decoder.c, lzma_common.h):
          # - if (is_literal_state(state)) → use UNMATCHED literal
          # - else → use MATCHED literal
          # - is_literal_state(state) = (state < LIT_STATES) where LIT_STATES = 7
          # - States 0-6: literal states (unmatched)
          # - States 7-11: non-literal states (matched after rep/match)
          #
          # @return [Boolean] True if state >= 7 (non-literal state)
          def use_matched_literal?
            @index >= 7
          end

          # Get state category
          #
          # Categorizes states for debugging and encoder logic.
          # The SDK doesn't expose this directly but uses state ranges
          # in various encoding decisions.
          #
          # @return [Symbol] State category
          def category
            case @index
            when 0..6
              CATEGORY_LITERAL
            when 7, 10
              CATEGORY_MATCH
            when 8, 11
              CATEGORY_REP
            when 9
              CATEGORY_SHORT_REP
            else
              raise "Invalid state: #{@index}"
            end
          end

          # Create a copy of this state
          #
          # Overrides parent to return StateMachine instance
          #
          # @return [StateMachine] A new StateMachine with the same index
          def dup
            StateMachine.new(@index)
          end

          # Check if state would use matched literal after match
          #
          # Helper method for encoder to determine encoding path.
          # Checks if encoding a match NOW would result in matched literal NEXT.
          #
          # @return [Boolean] True if state would transition to matched literal state
          def would_use_matched_literal?
            # After a match, we transition to MATCH_STATES[@index]
            next_state = MATCH_STATES[@index]
            next_state >= 7
          end
        end
      end
    end
  end
end
