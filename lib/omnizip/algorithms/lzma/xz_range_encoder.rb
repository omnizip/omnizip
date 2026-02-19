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
      # Range Encoder ported from XZ Utils range_encoder.c
      #
      # This class implements binary range coding, which is the core
      # compression algorithm for LZMA. Range coding is a form of
      # arithmetic coding that encodes bits into a compressed bitstream
      # using probability models.
      #
      # The encoder maintains a range [low, low+range) and narrows this
      # range as bits are encoded. When the range becomes too small, it
      # is normalized and output bytes are produced.
      #
      # Ported from XZ Utils liblzma/range_encoder.c
      class XZRangeEncoder
        TOP_VALUE = 1 << 24
        SHIFT_BITS = 8
        BIT_MODEL_TOTAL_BITS = 11
        BIT_MODEL_TOTAL = 1 << BIT_MODEL_TOTAL_BITS

        attr_reader :cache, :range, :low

        # Initialize a new range encoder
        #
        # @param output [IO] Output stream for compressed data
        def initialize(output)
          @output = output
          @low = 0
          @range = 0xFFFFFFFF
          @cache = 0
          @cache_size = 1
        end

        # Encode a single bit using probability model
        #
        # This method encodes a bit (0 or 1) using an adaptive probability
        # model. The probability model is updated after encoding to adapt
        # to the input data statistics.
        #
        # Ported from XZ Utils range_encoder.c rc_bit()
        #
        # @param model [BitModel] Probability model for this bit
        # @param bit [Integer] Bit value to encode (0 or 1)
        # @return [void]
        def encode_bit(model, bit)
          prob = model.probability
          bound = (@range >> BIT_MODEL_TOTAL_BITS) * prob

          if bit.zero?
            @range = bound
          else
            @low += bound
            @range -= bound
          end

          normalize! if @range < TOP_VALUE

          # Update probability model based on bit value
          # Matches decoder behavior (proper OOP symmetry)
          model.update(bit)
        end

        # Encode multiple bits as a bittree
        #
        # A bittree is a binary tree where each node has a probability model.
        # This method encodes a value by traversing the tree from the root,
        # encoding the bit at each node and following the corresponding branch.
        #
        # Ported from XZ Utils range_encoder.c rc_bittree()
        #
        # @param models [Array<BitModel>] Array of probability models for tree nodes
        # @param num_bits [Integer] Number of bits to encode
        # @param value [Integer] Value to encode
        # @return [void]
        def encode_bittree(models, num_bits, value)
          index = 1
          bit = num_bits - 1

          while bit >= 0
            bit_value = (value >> bit) & 1
            encode_bit(models[index - 1], bit_value)
            index = (index << 1) | bit_value
            bit -= 1
          end
        end

        # Encode multiple bits as a reverse bittree
        #
        # Similar to encode_bittree but processes bits in reverse order.
        # This is used for certain LZMA encoding operations.
        #
        # Ported from XZ Utils range_encoder.c rc_bittree_reverse()
        #
        # @param models [Array<BitModel>] Array of probability models for tree nodes
        # @param num_bits [Integer] Number of bits to encode
        # @param value [Integer] Value to encode
        # @return [void]
        def encode_bittree_reverse(models, num_bits, value)
          index = 1
          bit = 0

          while bit < num_bits
            bit_value = (value >> bit) & 1
            encode_bit(models[index - 1], bit_value)
            index = (index << 1) | bit_value
            bit += 1
          end
        end

        # Encode a direct bit (without probability model)
        #
        # This method encodes a bit with fixed 0.5 probability.
        # Used for encoding values where no adaptive model is available.
        #
        # Ported from XZ Utils range_encoder.c rc_direct()
        #
        # @param value [Integer] Value to encode (0 or 1)
        # @return [void]
        def encode_direct(value)
          @range >>= 1
          @low += @range if value != 0
          normalize! if @range < TOP_VALUE
        end

        # Flush pending data to output stream
        #
        # This method flushes any remaining data in the range encoder
        # to the output stream. This must be called before the encoder
        # is discarded.
        #
        # Ported from XZ Utils range_encoder.c rc_flush()
        #
        # @return [void]
        def flush!
          (5 - @cache_size).times do
            shift_low
          end
        end

        private

        # Normalize the range encoder state
        #
        # When the range becomes too small (< TOP_VALUE), it needs to be
        # normalized by shifting left and outputting bytes as needed.
        #
        # Ported from XZ Utils range_encoder.c rc_normalize()
        #
        # @return [void]
        def normalize!
          if @range < TOP_VALUE
            @range <<= SHIFT_BITS
            shift_low
          end
        end

        # Shift low value and output bytes as needed
        #
        # This method handles the carry propagation and byte output
        # for the range encoder. When the high byte of low changes,
        # it outputs bytes to the stream.
        #
        # Ported from XZ Utils range_encoder.c rc_shift_low()
        # See: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_encoder.h:140-186
        #
        # @return [void]
        def shift_low
          # Extract low 32 bits and high 32 bits (carry)
          # XZ Utils: if ((uint32_t)(rc->low) < (uint32_t)(0xFF000000) || (uint32_t)(rc->low >> 32) != 0)
          # This condition is TRUE when:
          #   - low32 < 0xFF000000 (the high byte of low is NOT 0xFF)
          #   - OR high != 0 (there's a carry from the low value)
          # When TRUE: write output bytes
          # When FALSE: increment cache_size (we're in a run of 0xFF bytes)
          low32 = @low & 0xFFFFFFFF
          high = (@low >> 32) & 0xFF

          if low32 < 0xFF000000 || high != 0
            # Write pending cache bytes (with carry if present)
            temp = @cache
            while @cache_size.positive?
              @output.putc((temp + high) & 0xFF)
              temp = 0xFF
              @cache_size -= 1
            end
            # Update cache to the high byte of low
            @cache = (low32 >> 24) & 0xFF
          else
            # High byte of low is 0xFF and no carry - increment pending count
            @cache_size += 1
          end

          # Shift low left by 8 bits (keeping only low 24 bits before shift)
          # XZ Utils: low = (low & 0x00FFFFFF) << RC_SHIFT_BITS;
          @low = (low32 & 0x00FFFFFF) << SHIFT_BITS
        end
      end
    end
  end
end
