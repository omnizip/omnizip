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
        attr_reader :code, :init_bytes_remaining

        # Initialize the range decoder
        #
        # @param input_stream [IO] The input stream of encoded bytes
        def initialize(input_stream)
          super
          @code = 0
          @initialization_complete = false
          @init_bytes_remaining = 5
          init_decoder
        end

        # Update the input stream (for LZMA2 multi-chunk streams)
        #
        # @param new_stream [IO] New input stream
        # @return [void]
        def update_stream(new_stream)
          @stream = new_stream
        end

        # Decode a single bit using a probability model
        #
        # This is the hottest method (~5 billion calls for a 600MB file).
        # normalize() and model.update() are inlined to eliminate method dispatch.
        #
        # @param model [BitModel] The probability model for this bit
        # @return [Integer] The decoded bit value (0 or 1)
        def decode_bit(model)
          # Inline normalize: only the hot path (range < TOP check)
          # Init bytes are handled eagerly in reset(), not here
          if @range < 0x01000000
            @range <<= 8
            byte = @stream.getbyte
            raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder normalization" if byte.nil?

            @code = ((@code << 8) | byte) & 0xFFFFFFFF
          end

          prob = model.probability
          bound = (@range >> 11) * prob

          if @code < bound
            @range = bound
            # Inline model.update(0): prob += (2048 - prob) >> 5
            model.probability = prob + ((2048 - prob) >> 5)
            0
          else
            @code -= bound
            @range -= bound
            # Inline model.update(1): prob -= prob >> 5
            model.probability = prob - (prob >> 5)
            1
          end
        end

        # Decode bits directly without using probability model
        #
        # @param num_bits [Integer] Number of bits to decode
        # @return [Integer] The decoded value
        def decode_direct_bits(num_bits)
          result = 0

          num_bits.downto(1) do |_i|
            # Inline normalize
            if @range < 0x01000000
              @range <<= 8
              byte = @stream.getbyte
              raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder normalization" if byte.nil?

              @code = ((@code << 8) | byte) & 0xFFFFFFFF
            end
            @range >>= 1

            bit = @code >= @range ? 1 : 0

            if bit == 1
              @code -= @range
              result = (result << 1) | 1
            else
              result = (result << 1) | 0
            end
          end

          result
        end

        # Decode a cumulative frequency value (PPMd)
        #
        # @param total_freq [Integer] Total frequency of all symbols in context
        # @return [Integer] The cumulative frequency value
        def decode_freq(total_freq)
          normalize
          range_freq = @range / total_freq
          @code / range_freq
        end

        # Normalize after decoding a symbol with frequency
        #
        # @param cum_freq [Integer] Cumulative frequency of decoded symbol
        # @param freq [Integer] Frequency of decoded symbol
        # @param total_freq [Integer] Total frequency of all symbols
        # @return [void]
        def normalize_freq(cum_freq, freq, total_freq)
          range_freq = @range / total_freq
          low_bound = range_freq * cum_freq
          high_bound = range_freq * (cum_freq + freq)

          @code -= low_bound
          @range = (high_bound - low_bound) & 0xFFFFFFFF
        end

        # Decode bits directly using a base value (XZ Utils rc_direct pattern)
        #
        # @param num_bits [Integer] Number of bits to decode
        # @param base [Integer] Base value to start from (2 or 3 for distances)
        # @return [Integer] The decoded value
        def decode_direct_bits_with_base(num_bits, base)
          result = base
          num_bits.times do |_i|
            result = (result << 1) + 1
            # Inline normalize
            if @range < 0x01000000
              @range <<= 8
              byte = @stream.getbyte
              raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder normalization" if byte.nil?

              @code = ((@code << 8) | byte) & 0xFFFFFFFF
            end
            @range >>= 1

            bit = @code >= @range ? 1 : 0

            if bit == 1
              @code -= @range
            else
              result -= 1
            end
          end
          result
        end

        # Reset the range decoder for a new chunk
        #
        # Resets state only. Call read_init_bytes after the stream is set
        # to the correct input.
        #
        # @return [void]
        def reset
          @range = 0xFFFFFFFF
          @code = 0
          @init_bytes_remaining = 5
        end

        # Eagerly read the 5 initialization bytes from the current stream.
        # Must be called after the stream is set to the correct input.
        #
        # @return [void]
        def read_init_bytes
          while @init_bytes_remaining.positive?
            byte = @stream.getbyte
            raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder initialization" if byte.nil?

            @code = ((@code << 8) | byte) & 0xFFFFFFFF
            @init_bytes_remaining -= 1
          end
        end

        # Normalize the range when it becomes too small
        #
        # Still needed for decode_freq() and other non-hot paths.
        # The hot-path methods inline normalize directly.
        #
        # @return [void]
        def normalize
          # Handle lazy initialization if needed (for non-hot paths)
          if @init_bytes_remaining.positive?
            while @init_bytes_remaining.positive?
              byte = @stream.getbyte
              raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder initialization" if byte.nil?

              @code = ((@code << 8) | byte) & 0xFFFFFFFF
              @init_bytes_remaining -= 1
            end
          end

          if @range < TOP
            byte = read_byte
            @range <<= 8
            @code = ((@code << 8) | byte) & 0xFFFFFFFF
          end
        end

        private

        # Initialize the decoder by reading the first bytes
        #
        # @return [void]
        def init_decoder
          5.times do
            @code = ((@code << 8) | read_byte) & 0xFFFFFFFF
            @init_bytes_remaining -= 1 if @init_bytes_remaining.positive?
          end
          @initialization_complete = true
        end

        # Read a single byte from the input stream
        #
        # @return [Integer] The byte value (0-255)
        # @raise [Omnizip::DecompressionError] If stream is exhausted during normal decoding
        def read_byte
          byte = @stream.getbyte

          if byte.nil? && @initialization_complete && @init_bytes_remaining.zero?
            raise Omnizip::DecompressionError,
                  "LZMA compressed data exhausted prematurely. The file may be corrupted or the uncompressed size field may be incorrect."
          end

          byte || 0
        end
      end
    end
  end
end
