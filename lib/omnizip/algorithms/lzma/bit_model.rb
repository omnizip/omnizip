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
      # Adaptive probability model for range coding
      #
      # This class manages probability states for individual bits in the
      # range coder. It uses adaptive arithmetic coding where probabilities
      # are updated based on actual bit values encountered during encoding
      # or decoding.
      #
      # Ported from XZ Utils range_encoder.c probability model implementation.
      class BitModel
        PROB_INIT = 1024  # Initial probability (0.5)
        MOVE_BITS = 5     # Probability update speed
        MAX_PROB = 1 << 11 # 4096
        BIT_MODEL_TOTAL = 0x800 # XZ Utils RC_BIT_MODEL_TOTAL = 2048

        attr_reader :probability

        # Initialize a new bit probability model
        #
        # @param initial_prob [Integer] Initial probability value (default: PROB_INIT)
        def initialize(initial_prob = PROB_INIT)
          @probability = initial_prob
        end

        # Update the probability model based on an actual bit value
        #
        # This method implements the XZ Utils adaptive algorithm:
        # - If bit is 0: probability increases (shifts toward encoding 0)
        # - If bit is 1: probability decreases (shifts toward encoding 1)
        #
        # The update uses a shift operation (MOVE_BITS) to control the
        # adaptation rate. Smaller MOVE_BITS means faster adaptation.
        #
        # XZ Utils formula (lzma/lzma_encoder.c:RC_BIT_*):
        #   bit 0: prob += (RC_BIT_MODEL_TOTAL - prob) >> RC_MOVE_BITS
        #   bit 1: prob -= prob >> RC_MOVE_BITS
        # where RC_BIT_MODEL_TOTAL = 2048, RC_MOVE_BITS = 5
        #
        # @param bit [Integer] The actual bit value (0 or 1)
        # @return [void]
        def update(bit)
          if bit.zero?
            # XZ Utils formula: prob += (RC_BIT_MODEL_TOTAL - prob) >> RC_MOVE_BITS
            @probability += ((BIT_MODEL_TOTAL - @probability) >> MOVE_BITS)
          else
            # XZ Utils formula: prob -= prob >> RC_MOVE_BITS
            @probability -= (@probability >> MOVE_BITS)
          end
        end

        # @deprecated Use {update} instead (same functionality, XZ Utils compatible)
        def update!(bit)
          update(bit)
        end

        # Reset the probability model to initial state
        #
        # @return [void]
        def reset
          @probability = PROB_INIT
        end

        # Get the probability of encoding a 0 bit
        #
        # @return [Integer] Probability value (0..MAX_PROB)
        def prob_0
          @probability
        end

        # Get the probability of encoding a 1 bit
        #
        # @return [Integer] Probability value (0..MAX_PROB)
        def prob_1
          MAX_PROB - @probability
        end

        # Create a copy of this bit model
        #
        # @return [BitModel] A new BitModel with the same probability
        def dup
          BitModel.new(@probability)
        end

        # For range coder: get probability scaled to 11 bits (XZ Utils compatibility)
        #
        # This method returns the probability value in the format expected
        # by the range coder for encoding/decoding operations.
        #
        # @return [Integer] Probability value (0..MAX_PROB)
        def to_range
          @probability
        end
      end
    end
  end
end
