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
require_relative "bit_model"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Base class for range encoding and decoding
      #
      # This class provides the core arithmetic coding functionality
      # used by both the encoder and decoder. Range coding is a form
      # of arithmetic coding that uses integer arithmetic to represent
      # probability ranges.
      #
      # The algorithm maintains a range [low, high) and subdivides it
      # based on symbol probabilities. The range is periodically
      # normalized to prevent arithmetic overflow/underflow.
      class RangeCoder
        include Constants

        attr_reader :range, :low

        # Initialize the range coder
        #
        # @param stream [IO] The input or output stream
        def initialize(stream)
          @stream = stream
          @range = 0xFFFFFFFF
          @low = 0
        end

        protected

        # Normalize the range when it becomes too small
        #
        # This is an abstract method to be implemented by subclasses.
        # The encoder and decoder have different normalization logic.
        #
        # @return [void]
        def normalize
          raise NotImplementedError,
                "#{self.class} must implement #normalize"
        end

        # Create an array of bit models for probability management
        #
        # @param size [Integer] Number of bit models to create
        # @return [Array<BitModel>] Array of initialized bit models
        def create_bit_models(size)
          Array.new(size) { BitModel.new }
        end

        # Get a bit model from an array based on index
        #
        # @param models [Array<BitModel>] Array of bit models
        # @param index [Integer] Index to retrieve
        # @return [BitModel] The bit model at the specified index
        def get_bit_model(models, index)
          models[index] ||= BitModel.new
        end
      end
    end
  end
end
