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

# Ported from XZ Utils src/liblzma/rangecoder/range_encoder.h
# Direct port of the reference implementation for byte-for-byte compatibility.

require_relative "range_coder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Range encoder for LZMA compression
      #
      # This is a direct port of XZ Utils' range encoder implementation
      # for guaranteed byte-for-byte compatibility.
      #
      # The encoder maintains a range [low, low+range) and subdivides
      # it proportionally based on symbol probabilities.
      class RangeEncoder < RangeCoder
        # Initialize the range encoder
        #
        # @param output_stream [IO] The output stream for encoded bytes
        def initialize(output_stream)
          super
          @cache = 0
          @cache_size = 1 # XZ Utils initializes to 1, not 0
          @pre_flush_pos = 0
        end

        # Encode a single bit using a probability model
        #
        # Ported from XZ Utils rc_encode() - RC_BIT_0 and RC_BIT_1 cases.
        # The key is that normalization happens BEFORE encoding the bit.
        #
        # IMPORTANT: We must emulate 32-bit unsigned arithmetic by masking
        # after each operation, since Ruby's integers are arbitrary precision.
        #
        # @param model [BitModel] The probability model for this bit
        # @param bit [Integer] The bit value (0 or 1)
        # @return [void]
        def encode_bit(model, bit)
          # Normalize BEFORE encoding (matches XZ Utils)
          normalize

          prob = model.probability

          # DEBUG: Trace is_rep bit encoding
          if ENV["TRACE_IS_REP_BITS"] && bit.zero?
            puts "  [RangeEncoder.encode_bit] BEFORE: range=#{@range}, low=#{@low}, prob=#{prob}, bit=#{bit}"
          end

          if bit.zero?
            # RC_BIT_0: shrink range to lower portion
            # rc->range = (rc->range >> 11) * prob
            # Emulate 32-bit unsigned multiplication with truncation
            @range = ((@range >> 11) * prob) & 0xFFFFFFFF
          else
            # RC_BIT_1: add bound to low, shrink range to upper portion
            # const uint32_t bound = prob * (rc->range >> 11)
            # rc->low += bound
            # rc->range -= bound
            bound = prob * (@range >> 11)
            @low = (@low + bound) & 0xFFFFFFFFFFFFFFFF # low can grow beyond 32 bits
            @range = (@range - bound) & 0xFFFFFFFF
          end

          if ENV["TRACE_IS_REP_BITS"] && bit.zero?
            puts "  [RangeEncoder.encode_bit] AFTER: range=#{@range}, low=#{@low}"
          end

          # Update probability model based on the bit value
          # This matches the decoder's update behavior (proper OOP symmetry)
          model.update(bit)
        end

        # Encode bits directly without using probability model
        #
        # Used for encoding values with uniform distribution.
        # Emulates 32-bit unsigned arithmetic.
        #
        # @param value [Integer] The value to encode
        # @param num_bits [Integer] Number of bits to encode
        # @return [void]
        def encode_direct_bits(value, num_bits)
          num_bits.downto(1) do |i|
            normalize
            @range = (@range >> 1) & 0xFFFFFFFF
            bit = (value >> (i - 1)) & 1
            @low = (@low + @range) & 0xFFFFFFFFFFFFFFFF if bit == 1
          end
        end

        # Encode a symbol using cumulative frequency range
        #
        # This is used by PPMd for encoding symbols based on their
        # frequency distribution in the current context.
        #
        # @param cum_freq [Integer] Cumulative frequency up to this symbol
        # @param freq [Integer] Frequency of this symbol
        # @param total_freq [Integer] Total frequency of all symbols in context
        # @return [void]
        def encode_freq(cum_freq, freq, total_freq)
          normalize
          range_freq = @range / total_freq
          low_bound = range_freq * cum_freq
          high_bound = range_freq * (cum_freq + freq)

          @low = (@low + low_bound) & 0xFFFFFFFFFFFFFFFF
          @range = (high_bound - low_bound) & 0xFFFFFFFF
        end

        # Flush remaining bytes to output stream
        #
        # Ported from XZ Utils rc_flush().
        #
        # @return [void]
        def flush
          # Store position BEFORE flush for LZMA2 compatibility
          # The decoder only needs bytes up to this point
          @pre_flush_pos = @stream.pos

          # Prevent further normalizations
          @range = 0xFFFFFFFF

          # Flush 5 bytes (see rc_flush() in xz)
          5.times { shift_low }
        end

        # Return bytes needed for decoding
        #
        # For LZMA2: returns pre-flush position (excludes 5-byte flush padding)
        # For regular LZMA: returns full output size
        #
        # @return [Integer] Number of bytes decoder will consume
        def bytes_for_decode
          @pre_flush_pos || @stream.pos
        end

        protected

        # Normalize the range when it becomes too small
        #
        # Ported from XZ Utils rc_encode() normalization logic.
        # IMPORTANT: shift_low is called BEFORE range is shifted!
        #
        # @return [void]
        def normalize
          while @range < TOP
            shift_low
            @range <<= 8
          end
        end

        private

        # Shift the top byte of 'low' to output
        #
        # Direct port of XZ Utils rc_shift_low() from range_encoder.h:136-159
        # Handles carry propagation through the cache mechanism.
        #
        # @return [void]
        def shift_low
          # if ((uint32_t)(rc->low) < (uint32_t)(0xFF000000)
          #     || (uint32_t)(rc->low >> 32) != 0)
          low_32 = @low & 0xFFFFFFFF
          carry = (@low >> 32) & 0xFF

          if low_32 < 0xFF000000 || carry != 0
            # do {
            #   out[*out_pos] = rc->cache + (uint8_t)(rc->low >> 32);
            #   ++*out_pos;
            #   rc->cache = 0xFF;
            # } while (--rc->cache_size != 0);
            loop do
              @stream.putc((@cache + carry) & 0xFF)
              @cache = 0xFF
              @cache_size -= 1
              break if @cache_size.zero?
            end

            # rc->cache = (rc->low >> 24) & 0xFF;
            @cache = (low_32 >> 24) & 0xFF
          end

          # ++rc->cache_size;
          @cache_size += 1

          # rc->low = (rc->low & 0x00FFFFFF) << RC_SHIFT_BITS;
          @low = (@low & 0x00FFFFFF) << 8
        end
      end
    end
  end
end
