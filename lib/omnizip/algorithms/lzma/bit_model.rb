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
      # The probability model maintains a value between 0 and BIT_MODEL_TOTAL
      # that represents the probability of encoding a 0 bit. The model
      # adapts by shifting toward the actual bit values seen, allowing
      # better compression of non-random data.
      class BitModel
        include Constants

        attr_reader :probability

        # Initialize a new bit probability model
        #
        # @param initial_prob [Integer] Initial probability value
        #   (default: INIT_PROBS which represents 0.5 probability)
        def initialize(initial_prob = INIT_PROBS)
          @probability = initial_prob
        end

        # Update the probability model based on an actual bit value
        #
        # This method implements the adaptive algorithm:
        # - If bit is 0: probability increases (shifts toward encoding 0)
        # - If bit is 1: probability decreases (shifts toward encoding 1)
        #
        # The update uses a shift operation (MOVE_BITS) to control the
        # adaptation rate. Smaller MOVE_BITS means faster adaptation.
        #
        # @param bit [Integer] The actual bit value (0 or 1)
        # @return [void]
        def update(bit)
          if bit.zero?
            # Increase probability of 0
            # prob += (BIT_MODEL_TOTAL - prob) >> MOVE_BITS
            @probability += ((BIT_MODEL_TOTAL - @probability) >> MOVE_BITS)
          else
            # Decrease probability of 0 (increase probability of 1)
            # prob -= prob >> MOVE_BITS
            @probability -= (@probability >> MOVE_BITS)
          end
        end

        # Reset the probability model to initial state
        #
        # @return [void]
        def reset
          @probability = INIT_PROBS
        end

        # Get the probability of encoding a 0 bit
        #
        # @return [Integer] Probability value (0..BIT_MODEL_TOTAL)
        def prob_0
          @probability
        end

        # Get the probability of encoding a 1 bit
        #
        # @return [Integer] Probability value (0..BIT_MODEL_TOTAL)
        def prob_1
          BIT_MODEL_TOTAL - @probability
        end

        # Create a copy of this bit model
        #
        # @return [BitModel] A new BitModel with the same probability
        def dup
          BitModel.new(@probability)
        end
      end
    end
  end
end
