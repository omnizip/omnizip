# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Container for all LZMA probability models
      # Ported from lzma_encoder_private.h
      class ProbabilityModels
        # Constants
        STATES = 12
        POS_STATES_MAX = 16
        LEN_LOW_SYMBOLS = 8
        LEN_MID_SYMBOLS = 8
        LEN_HIGH_SYMBOLS = 16
        LEN_SYMBOLS = 272
        MATCH_LEN_MIN = 2
        MATCH_LEN_MAX = 273
        DIST_STATES = 4
        DIST_SLOTS = 64
        DIST_MODEL_START = 4
        DIST_MODEL_END = 14
        FULL_DISTANCES = 128
        ALIGN_SIZE = 16

        attr_accessor :literal, :is_match, :is_rep,
                      :is_rep0, :is_rep1, :is_rep2, :is_rep0_long,
                      :dist_slot, :dist_special, :dist_align,
                      :match_len_encoder, :rep_len_encoder

        def initialize(lc: 3, lp: 0, pb: 2)
          @lc = lc
          @lp = lp
          @pb = pb

          @literal = init_literal_models
          @is_match = init_is_match_models
          @is_rep = init_array(STATES, BitModel)
          @is_rep0 = init_array(STATES, BitModel)
          @is_rep1 = init_array(STATES, BitModel)
          @is_rep2 = init_array(STATES, BitModel)
          @is_rep0_long = init_is_rep0_long_models
          @dist_slot = init_dist_slot_models
          @dist_special = init_array(FULL_DISTANCES - DIST_MODEL_END, BitModel)
          @dist_align = init_array(ALIGN_SIZE, BitModel)
        end

        private

        def init_literal_models
          num_contexts = 1 << (@lc + @lp)
          Array.new(num_contexts * 0x300) { BitModel.new }
        end

        def init_is_match_models
          Array.new(STATES * (1 << @pb)) { BitModel.new }
        end

        def init_is_rep0_long_models
          Array.new(STATES * (1 << @pb)) { BitModel.new }
        end

        def init_dist_slot_models
          Array.new(DIST_STATES * DIST_SLOTS) { BitModel.new }
        end

        def init_array(size, _model_class)
          Array.new(size) { BitModel.new }
        end
      end
    end
  end
end
