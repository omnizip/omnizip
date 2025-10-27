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
    class PPMd7 < Algorithm
      # Represents a symbol's state within a context
      #
      # Each symbol that appears after a context has an associated
      # state that tracks its frequency. This is used to calculate
      # the probability of each symbol appearing next.
      class SymbolState
        attr_reader :symbol
        attr_accessor :freq

        # Initialize a new symbol state
        #
        # @param symbol [Integer] The symbol value (0-255)
        # @param freq [Integer] Initial frequency (default: 1)
        def initialize(symbol, freq = 1)
          @symbol = symbol
          @freq = freq
        end

        # Get the probability of this symbol
        #
        # The probability is proportional to the frequency.
        # This is used by the range coder to encode/decode.
        #
        # @param total_freq [Integer] Total frequency in context
        # @return [Float] Probability (0.0 to 1.0)
        def probability(total_freq)
          @freq.to_f / total_freq
        end
      end
    end
  end
end
