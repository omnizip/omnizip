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
      # Range decoder for LZMA decompression
      #
      # This class implements the decoding side of arithmetic coding
      # using integer range arithmetic. It decodes bits from the
      # compressed byte stream based on their probability models.
      #
      # The decoder mirrors the encoder's range subdivisions to
      # extract the original bit values. It maintains a code value
      # that represents the current position within the range.
      class RangeDecoder < RangeCoder
        attr_reader :code

        # Initialize the range decoder
        #
        # @param input_stream [IO] The input stream of encoded bytes
        def initialize(input_stream)
          super
          @code = 0
          init_decoder
        end

        # Decode a single bit using a probability model
        #
        # The range is split based on the bit's probability,
        # and the code value determines which portion contains
        # the actual bit value.
        #
        # @param model [BitModel] The probability model for this bit
        # @return [Integer] The decoded bit value (0 or 1)
        def decode_bit(model)
          bound = (@range >> 11) * model.probability

          if @code < bound
            @range = bound
            model.update(0)
            normalize
            0
          else
            @code -= bound
            @range -= bound
            model.update(1)
            normalize
            1
          end
        end

        # Decode bits directly without using probability model
        #
        # This is used for decoding values with uniform distribution
        # where all bit values are equally likely.
        #
        # @param num_bits [Integer] Number of bits to decode
        # @return [Integer] The decoded value
        def decode_direct_bits(num_bits)
          result = 0

          num_bits.downto(1) do
            normalize
            @range >>= 1

            if @code >= @range
              @code -= @range
              result = (result << 1) | 1
            else
              result = (result << 1) | 0
            end
          end

          result
        end

        protected

        # Normalize the range when it becomes too small
        #
        # When range drops below TOP threshold, shift in a new
        # byte from the input stream and scale up the range by 256.
        #
        # @return [void]
        def normalize
          return unless @range < TOP

          @range <<= 8
          @code = (@code << 8) | read_byte
        end

        private

        # Initialize the decoder by reading the first bytes
        #
        # @return [void]
        def init_decoder
          5.times do
            @code = (@code << 8) | read_byte
          end
        end

        # Read a single byte from the input stream
        #
        # @return [Integer] The byte value (0-255)
        def read_byte
          byte = @stream.getbyte
          byte.nil? ? 0 : byte
        end
      end
    end
  end
end
