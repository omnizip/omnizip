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

# Ported from 7-Zip SDK C/LzmaEnc.c
# Direct port of the LZMA SDK range encoder for byte-for-byte compatibility
# with 7-Zip archives.

require_relative "../../../algorithms/lzma/range_coder"
require_relative "../../../algorithms/lzma/constants"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # Range encoder for 7-Zip SDK LZMA compression
        #
        # This is a direct port of 7-Zip SDK's range encoder implementation
        # from LzmaEnc.c for guaranteed compatibility with 7-Zip archives.
        #
        # KEY DIFFERENCE from XZ Utils:
        # - 7-Zip SDK normalizes AFTER encoding each bit
        # - XZ Utils normalizes BEFORE encoding each bit
        #
        # This difference produces different output bytes, so we need
        # separate implementations for 7-Zip and XZ Utils compatibility.
        #
        # Reference: /Users/mulgogi/src/external/7-Zip/C/LzmaEnc.c lines 730-784
        class RangeEncoder
          include Omnizip::Algorithms::LZMA::Constants

          # Initialize the range encoder
          #
          # @param output_stream [IO] The output stream for encoded bytes
          def initialize(output_stream)
            @stream = output_stream
            @low = 0
            @range = 0xFFFFFFFF # Full 32-bit range
            @cache = 0
            @cache_size = 1 # SDK initializes to 1
            @pre_flush_pos = 0
          end

          # Encode a single bit using a probability model
          #
          # Ported from 7-Zip SDK RC_BIT() macro (LzmaEnc.c lines 750-765)
          # The key difference is that normalization happens AFTER encoding.
          #
          # SDK macro:
          #   #define RC_BIT(p, prob, bit) { \
          #     RC_BIT_PRE(p, prob) \
          #     if (bit == 0) { range = newBound; ttt += (kBitModelTotal - ttt) >> kNumMoveBits; } \
          #     else { (p)->low += newBound; range -= newBound; ttt -= ttt >> kNumMoveBits; } \
          #     *(prob) = (CLzmaProb)ttt; \
          #     RC_NORM(p) \
          #   }
          #
          # @param model [BitModel] The probability model for this bit
          # @param bit [Integer] The bit value (0 or 1)
          # @return [void]
          def encode_bit(model, bit)
            prob = model.probability

            # RC_BIT_PRE: Calculate newBound = (range >> kNumBitModelTotalBits) * prob
            new_bound = (@range >> 11) * prob

            new_prob = if bit.zero?
                         # RC_BIT_0: shrink range to lower portion
                         @range = new_bound & 0xFFFFFFFF
                         # Update probability: ttt += (kBitModelTotal - ttt) >> kNumMoveBits
                         prob + ((BIT_MODEL_TOTAL - prob) >> MOVE_BITS)
                       else
                         # RC_BIT_1: add bound to low, shrink range to upper portion
                         @low = (@low + new_bound) & 0xFFFFFFFFFFFFFFFF
                         @range = (@range - new_bound) & 0xFFFFFFFF
                         # Update probability: ttt -= ttt >> kNumMoveBits
                         prob - (prob >> MOVE_BITS)
                       end
            model.instance_variable_set(:@probability, new_prob)

            # RC_NORM: Normalize AFTER encoding (key SDK difference!)
            normalize
          end

          # Encode bits directly without using probability model
          #
          # Used for encoding values with uniform distribution (e.g., distance
          # high bits).
          #
          # @param value [Integer] The value to encode
          # @param num_bits [Integer] Number of bits to encode
          # @return [void]
          def encode_direct_bits(value, num_bits)
            num_bits.times do |i|
              @range >>= 1
              @range &= 0xFFFFFFFF
              bit = (value >> (num_bits - 1 - i)) & 1
              @low = (@low + @range) & 0xFFFFFFFFFFFFFFFF if bit == 1
              normalize
            end
          end

          # Flush remaining bytes to output stream
          #
          # Writes the final bytes to complete the range coding stream.
          #
          # @return [void]
          def flush
            # Store position BEFORE flush for compatibility
            @pre_flush_pos = @stream.pos

            # Prevent further normalizations
            @range = 0xFFFFFFFF

            # Flush 5 bytes (matches SDK behavior)
            5.times { shift_low }
          end

          # Return bytes needed for decoding
          #
          # @return [Integer] Number of bytes decoder will consume
          def bytes_for_decode
            @pre_flush_pos || @stream.pos
          end

          # Get current output position
          #
          # @return [Integer] Current position in output stream
          def pos
            @stream.pos
          end

          private

          # Normalize the range when it becomes too small
          #
          # Ported from 7-Zip SDK RC_NORM macro (LzmaEnc.c line 730):
          #   #define RC_NORM(p) if (range < kTopValue) { range <<= 8; RangeEnc_ShiftLow(p); }
          #
          # @return [void]
          def normalize
            while @range < TOP
              @range <<= 8
              @range &= 0xFFFFFFFF
              shift_low
            end
          end

          # Shift the top byte of 'low' to output
          #
          # Ported from 7-Zip SDK RangeEnc_ShiftLow().
          # Handles carry propagation through the cache mechanism.
          #
          # Reference: 7-Zip SDK C/LzmaEnc.c RangeEnc_ShiftLow
          #
          # @return [void]
          def shift_low
            low_32 = @low & 0xFFFFFFFF
            carry = (@low >> 32) & 0xFF

            if low_32 < 0xFF000000 || carry != 0
              loop do
                @stream.putc((@cache + carry) & 0xFF)
                @cache = 0xFF
                @cache_size -= 1
                break if @cache_size.zero?
              end

              @cache = (low_32 >> 24) & 0xFF
            end

            @cache_size += 1
            @low = (@low & 0x00FFFFFF) << 8
          end
        end
      end
    end
  end
end
