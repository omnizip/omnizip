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

require_relative "range_coder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Range encoder for LZMA compression
      #
      # This class implements the encoding side of arithmetic coding
      # using integer range arithmetic. It encodes bits based on their
      # probability models, producing a compressed byte stream.
      #
      # The encoder maintains a range [low, low+range) and subdivides
      # it proportionally based on symbol probabilities. When the range
      # becomes too small, it is normalized by shifting bytes to output.
      class RangeEncoder < RangeCoder
        # Initialize the range encoder
        #
        # @param output_stream [IO] The output stream for encoded bytes
        def initialize(output_stream)
          super
          @cache = 0
          @cache_size = 1
        end

        # Encode a single bit using a probability model
        #
        # The range is split based on the bit's probability:
        # - If bit is 0: use lower portion of range
        # - If bit is 1: use upper portion of range
        #
        # @param model [BitModel] The probability model for this bit
        # @param bit [Integer] The bit value (0 or 1)
        # @return [void]
        def encode_bit(model, bit)
          bound = (@range >> 11) * model.probability

          if bit.zero?
            @range = bound
            model.update(0)
          else
            @low += bound
            @range -= bound
            model.update(1)
          end

          normalize
        end

        # Encode bits directly without using probability model
        #
        # This is used for encoding values with uniform distribution
        # where all bit values are equally likely.
        #
        # @param value [Integer] The value to encode
        # @param num_bits [Integer] Number of bits to encode
        # @return [void]
        def encode_direct_bits(value, num_bits)
          num_bits.downto(1) do |i|
            normalize
            @range >>= 1
            bit = (value >> (i - 1)) & 1
            @low += @range if bit == 1
          end
        end

        # Flush remaining bytes to output stream
        #
        # This method ensures all encoded data is written to the
        # output stream. Must be called after encoding is complete.
        #
        # @return [void]
        def flush
          5.times { shift_low }
        end

        protected

        # Normalize the range when it becomes too small
        #
        # When range drops below TOP threshold, shift out the
        # top byte of 'low' to the output stream and scale up
        # the range by 256.
        #
        # @return [void]
        def normalize
          shift_low while @range < TOP
        end

        private

        # Shift the top byte of 'low' to output
        #
        # This implements the byte-oriented output of the range coder.
        # Handles carry propagation through the cache mechanism.
        #
        # @return [void]
        def shift_low
          if @low < 0xFF000000 || (@low >> 32) != 0
            temp = @cache

            loop do
              @stream.putc(temp + (@low >> 32))
              temp = 0xFF
              @cache_size -= 1
              break if @cache_size <= 0
            end

            @cache = (@low >> 24) & 0xFF
            @cache_size = 1
          else
            @cache_size += 1
          end

          @low = (@low << 8) & 0xFFFFFFFF
          @range <<= 8
        end
      end
    end
  end
end
