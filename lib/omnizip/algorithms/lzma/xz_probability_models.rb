# frozen_string_literal: true

require_relative "xz_buffered_range_encoder"
require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible probability models
      #
      # Organizes all probability models used by LZMA encoder, matching
      # XZ Utils structure exactly. All models start at probability 1024
      # (BIT_MODEL_TOTAL / 2 = 0.5 probability).
      #
      # Uses XzBufferedRangeEncoder::Probability for mutable inline updates.
      #
      # Based on: xz/src/liblzma/lzma/lzma_encoder_private.h
      class XzProbabilityModels
        include Constants

        # Literal context models
        attr_reader :literal

        # Match type models
        attr_reader :is_match, :is_rep, :is_rep0, :is_rep1, :is_rep2
        attr_reader :is_rep0_long

        # Distance models
        attr_reader :dist_slot, :dist_special, :dist_align

        # Length encoders
        attr_reader :match_len_encoder, :rep_len_encoder

        # Initialize all probability models
        #
        # @param lc [Integer] Number of literal context bits (0-8)
        # @param lp [Integer] Number of literal position bits (0-4)
        # @param pb [Integer] Number of position bits (0-4)
        def initialize(lc, lp, pb)
          @lc = lc
          @lp = lp
          @pb = pb

          init_literal_models(lc, lp)
          init_match_models(pb)
          init_distance_models
          init_length_encoders(pb)
        end

        # Reset all probability models to initial state
        def reset
          reset_literal_models
          reset_match_models
          reset_distance_models
          reset_length_encoders
        end

        private

        # Initialize literal context models
        # Ported from XZ Utils literal_init() in lzma_common.h
        # Size: LITERAL_CODER_SIZE << (lc + lp) = 0x300 * (1 << (lc + lp))
        # This is a FLAT array, not 2D, to match XZ Utils structure
        def init_literal_models(lc, lp)
          coders = 0x300 << (lc + lp)
          @literal = Array.new(coders) { XzBufferedRangeEncoder::Probability.new }
        end

        # Initialize match type models
        def init_match_models(pb)
          num_pos_states = 1 << pb

          # is_match[state][pos_state]
          @is_match = Array.new(NUM_STATES) do
            Array.new(num_pos_states) { XzBufferedRangeEncoder::Probability.new }
          end

          # is_rep[state]
          @is_rep = Array.new(NUM_STATES) { XzBufferedRangeEncoder::Probability.new }

          # is_rep0[state]
          @is_rep0 = Array.new(NUM_STATES) { XzBufferedRangeEncoder::Probability.new }

          # is_rep1[state]
          @is_rep1 = Array.new(NUM_STATES) { XzBufferedRangeEncoder::Probability.new }

          # is_rep2[state]
          @is_rep2 = Array.new(NUM_STATES) { XzBufferedRangeEncoder::Probability.new }

          # is_rep0_long[state][pos_state]
          @is_rep0_long = Array.new(NUM_STATES) do
            Array.new(num_pos_states) { XzBufferedRangeEncoder::Probability.new }
          end
        end

        # Initialize distance models
        def init_distance_models
          # dist_slot[len_to_pos_state][dist_slot]
          # len_to_pos_state: 0-3 (maps match length to state)
          # dist_slot: 0-63 (6-bit distance slot)
          @dist_slot = Array.new(NUM_LEN_TO_POS_STATES) do
            Array.new(NUM_DIST_SLOTS) { XzBufferedRangeEncoder::Probability.new }
          end

          # dist_special[dist - 4] for slots 4-13 (160 models)
          # Each slot has varying number of bits encoded with models
          num_dist_special = NUM_FULL_DISTANCES - START_POS_MODEL_INDEX
          @dist_special = Array.new(num_dist_special) { XzBufferedRangeEncoder::Probability.new }

          # dist_align[align_bit] for alignment (16 models)
          @dist_align = Array.new(DIST_ALIGN_SIZE) { XzBufferedRangeEncoder::Probability.new }
        end

        # Initialize length encoders
        def init_length_encoders(pb)
          @match_len_encoder = LengthEncoder.new(pb)
          @rep_len_encoder = LengthEncoder.new(pb)
        end

        # Reset methods
        def reset_literal_models
          @literal.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
        end

        def reset_match_models
          @is_match.each do |pos_states|
            pos_states.each do |prob|
              prob.value = BIT_MODEL_TOTAL >> 1
            end
          end
          @is_rep.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
          @is_rep0.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
          @is_rep1.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
          @is_rep2.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
          @is_rep0_long.each do |pos_states|
            pos_states.each do |prob|
              prob.value = BIT_MODEL_TOTAL >> 1
            end
          end
        end

        def reset_distance_models
          @dist_slot.each do |slots|
            slots.each do |prob|
              prob.value = BIT_MODEL_TOTAL >> 1
            end
          end
          @dist_special.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
          @dist_align.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }
        end

        def reset_length_encoders
          @match_len_encoder.reset
          @rep_len_encoder.reset
        end
      end

      # Length encoder with probability models and price tables
      #
      # Encodes match lengths using a 3-tier structure:
      # - Low: lengths 2-9 (choice=0, 3 bits)
      # - Mid: lengths 10-17 (choice=1, choice2=0, 3 bits)
      # - High: lengths 18-273 (choice=1, choice2=1, 8 bits)
      class LengthEncoder
        include Constants

        attr_reader :choice, :choice2, :low, :mid, :high, :prices, :counters

        # Initialize length encoder
        #
        # @param pb [Integer] Number of position bits
        def initialize(pb)
          @pb = pb
          @num_pos_states = 1 << pb

          # Choice bits
          @choice = XzBufferedRangeEncoder::Probability.new
          @choice2 = XzBufferedRangeEncoder::Probability.new

          # Low lengths (per position state)
          @low = Array.new(@num_pos_states) do
            Array.new(LEN_LOW_SYMBOLS) { XzBufferedRangeEncoder::Probability.new }
          end

          # Mid lengths (per position state)
          @mid = Array.new(@num_pos_states) do
            Array.new(LEN_MID_SYMBOLS) { XzBufferedRangeEncoder::Probability.new }
          end

          # High lengths (shared across position states)
          @high = Array.new(LEN_HIGH_SYMBOLS) { XzBufferedRangeEncoder::Probability.new }

          # Price tables (updated incrementally)
          # prices[pos_state][length - MATCH_LEN_MIN]
          @prices = Array.new(@num_pos_states) do
            Array.new(MATCH_LEN_MAX - MATCH_LEN_MIN + 1, 0)
          end

          # Counters for price table updates
          @counters = Array.new(@num_pos_states, 0)
        end

        # Reset all models to initial state
        def reset
          @choice.value = BIT_MODEL_TOTAL >> 1
          @choice2.value = BIT_MODEL_TOTAL >> 1
          @low.each do |models|
            models.each do |prob|
              prob.value = BIT_MODEL_TOTAL >> 1
            end
          end
          @mid.each do |models|
            models.each do |prob|
              prob.value = BIT_MODEL_TOTAL >> 1
            end
          end
          @high.each { |prob| prob.value = BIT_MODEL_TOTAL >> 1 }

          # Reset price tables
          @prices.each { |pos_prices| pos_prices.fill(0) }
          @counters.fill(0)
        end

        # Get price for encoding length at position state
        #
        # @param pos_state [Integer] Position state (0 to 2^pb - 1)
        # @param length [Integer] Match length (2 to 273)
        # @return [Integer] Price in price units
        def get_price(pos_state, length)
          @prices[pos_state][length - MATCH_LEN_MIN]
        end

        # Set price for length at position state
        #
        # @param pos_state [Integer] Position state
        # @param length [Integer] Match length
        # @param price [Integer] Price value
        def set_price(pos_state, length, price)
          @prices[pos_state][length - MATCH_LEN_MIN] = price
        end

        # Decrement counter for position state
        #
        # @param pos_state [Integer] Position state
        # @return [Boolean] True if counter reached zero
        def decrement_counter(pos_state)
          @counters[pos_state] -= 1
          @counters[pos_state] <= 0
        end

        # Reset counter for position state
        #
        # @param pos_state [Integer] Position state
        # @param value [Integer] Counter value
        def reset_counter(pos_state, value)
          @counters[pos_state] = value
        end
      end
    end
  end
end
