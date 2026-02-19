# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible LZMA state machine
      #
      # Tracks encoding context via 12-state machine to predict
      # optimal probability models for upcoming symbols.
      #
      # Based on: xz/src/liblzma/lzma/lzma_common.h
      class XzState
        # 12 LZMA states (matching XZ Utils exactly)
        STATE_LIT_LIT = 0           # literal after literal
        STATE_MATCH_LIT_LIT = 1     # literal after literal after match
        STATE_REP_LIT_LIT = 2       # literal after literal after rep
        STATE_SHORTREP_LIT_LIT = 3  # literal after literal after shortrep
        STATE_MATCH_LIT = 4         # literal after match
        STATE_REP_LIT = 5           # literal after rep
        STATE_SHORTREP_LIT = 6      # literal after shortrep
        STATE_LIT_MATCH = 7         # match after literal
        STATE_LIT_LONGREP = 8       # longrep after literal
        STATE_LIT_SHORTREP = 9      # shortrep after literal
        STATE_NONLIT_MATCH = 10     # match after non-literal
        STATE_NONLIT_REP = 11       # rep after non-literal

        LIT_STATES = 7 # States 0-6 indicate previous was literal

        attr_accessor :value

        def initialize(initial = STATE_LIT_LIT)
          @value = initial
        end

        # Update state after encoding literal
        # Matches XZ Utils update_literal() macro
        def update_literal
          old_value = @value
          @value = if @value <= STATE_SHORTREP_LIT_LIT
                     STATE_LIT_LIT
                   elsif @value <= STATE_LIT_SHORTREP
                     @value - 3
                   else
                     @value - 6
                   end
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: update_literal - state: #{old_value} → #{@value}"
          end
        end

        # Update state after encoding match
        # Matches XZ Utils update_match() macro
        def update_match
          old_value = @value
          @value = @value < LIT_STATES ? STATE_LIT_MATCH : STATE_NONLIT_MATCH
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: update_match - state: #{old_value} → #{@value}"
          end
        end

        # Update state after encoding long rep match
        # Matches XZ Utils update_long_rep() macro
        def update_long_rep
          @value = @value < LIT_STATES ? STATE_LIT_LONGREP : STATE_NONLIT_REP
        end

        # Update state after encoding short rep (1 byte)
        # Matches XZ Utils update_short_rep() macro
        def update_short_rep
          @value = @value < LIT_STATES ? STATE_LIT_SHORTREP : STATE_NONLIT_REP
        end

        # Check if previous symbol was literal
        def literal_state?
          @value < LIT_STATES
        end

        # Create a copy of this state
        def dup
          XzState.new(@value)
        end

        # Reset to initial state
        def reset
          @value = STATE_LIT_LIT
        end

        # Check if state is valid
        def valid?
          @value.between?(STATE_LIT_LIT, STATE_NONLIT_REP)
        end

        # String representation for debugging
        def to_s
          STATE_NAMES[@value] || "INVALID(#{@value})"
        end

        # State names for debugging
        STATE_NAMES = {
          STATE_LIT_LIT => "STATE_LIT_LIT",
          STATE_MATCH_LIT_LIT => "STATE_MATCH_LIT_LIT",
          STATE_REP_LIT_LIT => "STATE_REP_LIT_LIT",
          STATE_SHORTREP_LIT_LIT => "STATE_SHORTREP_LIT_LIT",
          STATE_MATCH_LIT => "STATE_MATCH_LIT",
          STATE_REP_LIT => "STATE_REP_LIT",
          STATE_SHORTREP_LIT => "STATE_SHORTREP_LIT",
          STATE_LIT_MATCH => "STATE_LIT_MATCH",
          STATE_LIT_LONGREP => "STATE_LIT_LONGREP",
          STATE_LIT_SHORTREP => "STATE_LIT_SHORTREP",
          STATE_NONLIT_MATCH => "STATE_NONLIT_MATCH",
          STATE_NONLIT_REP => "STATE_NONLIT_REP",
        }.freeze
      end
    end
  end
end
