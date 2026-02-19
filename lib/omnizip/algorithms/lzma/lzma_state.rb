# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZMA State Machine
      # Ported from XZ Utils lzma_common.h and lzma_decoder.c
      class LZMAState
        # State transition table (from lzma_decoder.c)
        TRANSITIONS = {
          # Literal after literal (matches XZ Utils update_literal macro)
          update_literal: {
            0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 1, 5 => 2,
            6 => 3, 7 => 4, 8 => 5, 9 => 6, 10 => 4, 11 => 5
          }.freeze,

          # Matched literal (literal after match, matches XZ Utils update_literal_matched macro)
          # Only called when previous state was NOT a literal (states 7-11)
          update_literal_matched: {
            0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 1, 5 => 2,
            6 => 3, 7 => 4, 8 => 5, 9 => 6, 10 => 4, 11 => 5
          }.freeze,

          # Regular match
          update_match: {
            0 => 7, 1 => 7, 2 => 7, 3 => 7, 4 => 7, 5 => 7,
            6 => 7, 7 => 10, 8 => 10, 9 => 10, 10 => 10, 11 => 10
          }.freeze,

          # Repeat match
          update_rep: {
            0 => 8, 1 => 8, 2 => 8, 3 => 8, 4 => 8, 5 => 8,
            6 => 8, 7 => 11, 8 => 11, 9 => 11, 10 => 11, 11 => 11
          }.freeze,

          # Short repeat (length=1)
          update_short_rep: {
            0 => 9, 1 => 9, 2 => 9, 3 => 9, 4 => 9, 5 => 9,
            6 => 9, 7 => 11, 8 => 11, 9 => 11, 10 => 11, 11 => 11
          }.freeze,

          # Long repeat (length>1)
          # Ported from XZ Utils: state < LIT_STATES ? STATE_LIT_LONGREP : STATE_NONLIT_REP
          # where LIT_STATES=7, STATE_LIT_LONGREP=8, STATE_NONLIT_REP=11
          update_long_rep: {
            0 => 8, 1 => 8, 2 => 8, 3 => 8, 4 => 8, 5 => 8,
            6 => 8, 7 => 11, 8 => 11, 9 => 11, 10 => 11, 11 => 11
          }.freeze,
        }.freeze

        attr_reader :value, :reps

        def initialize(value = 0)
          @value = value
          @reps = [0, 0, 0, 0] # Initial repeat distances (matches XZ Utils)
        end

        # After encoding a literal
        def update_literal!
          @value = if use_matched_literal?
                     TRANSITIONS[:update_literal_matched][@value]
                   else
                     TRANSITIONS[:update_literal][@value]
                   end
        end

        # After encoding a regular match
        def update_match!(distance)
          @value = TRANSITIONS[:update_match][@value]
          rotate_reps!(distance)
        end

        # After encoding a repeat match
        def update_rep!(rep_index)
          @value = TRANSITIONS[:update_rep][@value]
          rotate_reps_for_rep!(rep_index)
        end

        # After encoding a short rep (length=1)
        def update_short_rep!
          @value = TRANSITIONS[:update_short_rep][@value]
        end

        # After encoding a long rep (length>1)
        # Ported from XZ Utils update_long_rep macro
        def update_long_rep!
          @value = TRANSITIONS[:update_long_rep][@value]
        end

        # Check if we should use matched literal encoding
        # XZ Utils logic: is_literal_state(state) = (state < LIT_STATES)
        # where LIT_STATES = 7
        # States 0-6: literal states (use unmatched literal)
        # States 7-11: non-literal states (use matched literal)
        def use_matched_literal?
          @value >= 7
        end

        # Repeat distance rotation
        def rotate_reps!(distance)
          @reps[3] = @reps[2]
          @reps[2] = @reps[1]
          @reps[1] = @reps[0]
          @reps[0] = distance
        end

        private

        def rotate_reps_for_rep!(rep_index)
          case rep_index
          when 0
            # Keep rep0, no rotation
          when 1
            # rep1 -> rep0
            @reps[0], @reps[1] = @reps[1], @reps[0]
          when 2
            # rep2 -> rep0, rep0 -> rep1, rep1 -> rep2
            @reps[0], @reps[1], @reps[2] = @reps[2], @reps[0], @reps[1]
          when 3
            # rep3 -> rep0, rotate others
            @reps[0], @reps[1], @reps[2], @reps[3] =
              @reps[3], @reps[0], @reps[1], @reps[2]
          end
        end
      end
    end
  end
end
