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
      # Literal byte encoder
      #
      # This class is responsible for encoding literal bytes using
      # probability models. It supports two modes:
      #
      # 1. Unmatched mode: Simple 8-bit encoding
      # 2. Matched mode: Uses match byte for context (SDK feature)
      #
      # The matched mode improves compression when a literal follows
      # a match, by using the corresponding byte from the match as
      # context for probability modeling.
      #
      # Single Responsibility: Literal byte encoding only
      #
      # @example Unmatched encoding
      #   encoder = LiteralEncoder.new
      #   encoder.encode_unmatched(byte, lit_state, range_encoder, models)
      #
      # @example Matched encoding (SDK mode)
      #   encoder = LiteralEncoder.new
      #   encoder.encode_matched(byte, match_byte, lit_state, range_encoder, models)
      class LiteralEncoder
        include Constants

        # Initialize the literal encoder
        #
        # @param lc [Integer] Literal context bits (0-8)
        # Default to 3 for compatibility
        def initialize(lc = 3)
          @lc = lc
        end

        # Encode literal byte in unmatched mode
        #
        # This is the standard LZMA literal encoding where each bit
        # is encoded using probability models based on the partial
        # symbol value.
        #
        # # XZ Utils literal_subcoder macro (from lzma_common.h:141-145):
        # # ((probs) + 3 * (((((pos) << 8) + (prev_byte)) & (literal_mask)) << (lc))
        #
        # @param byte [Integer] Byte value to encode (0-255)
        # @param pos [Integer] Current position in stream
        # @param prev_byte [Integer] Previous byte value
        # @param lc [Integer] Literal context bits (0-8)
        # @param literal_mask [Integer] Literal mask for context calculation
        # @param range_encoder [RangeEncoder] Range encoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [void]
        def encode_unmatched(byte, pos, prev_byte, lc, literal_mask,
range_encoder, models)
          # Calculate base_offset using XZ Utils formula
          # (((pos << 8) + prev_byte) & literal_mask) << lc
          context = (((pos << 8) + prev_byte) & literal_mask)
          base_offset = 3 * (context << lc)
          model_index = 1
          bit_count = 8

          loop do
            # const uint32_t bit = (symbol >> --bit_count) & 1;
            bit_count -= 1
            bit = (byte >> bit_count) & 1

            # rc_bit(rc, &probs[model_index], bit);
            range_encoder.encode_bit(models[base_offset + model_index], bit)

            # model_index = (model_index << 1) + bit;
            model_index = (model_index << 1) + bit

            break if bit_count.zero?
          end
        end

        # Encode literal byte in matched mode (SDK feature)
        #
        # This mode uses a byte from the dictionary (the "match byte")
        # as context for encoding the literal. This improves compression
        # when the literal follows a match, as the match byte provides
        # additional predictive information.
        #
        # Direct port from XZ Utils literal_matched() in lzma_encoder.c:22-41
        #
        # @param byte [Integer] Byte value to encode (0-255)
        # @param match_byte [Integer] Corresponding byte from dictionary
        # @param pos [Integer] Current position in stream
        # @param prev_byte [Integer] Previous byte value
        # @param lc [Integer] Literal context bits (0-8)
        # @param literal_mask [Integer] Literal mask for context calculation
        # @param range_encoder [RangeEncoder] Range encoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [void]
        def encode_matched(byte, match_byte, pos, prev_byte, lc, literal_mask,
range_encoder, models)
          # Direct port of xz's literal_matched
          # static inline void
          # literal_matched(lzma_range_encoder *rc, probability *subcoder,
          #     uint32_t match_byte, uint32_t symbol)
          # {
          #   uint32_t offset = 0x100;
          #   symbol += UINT32_C(1) << 8;
          #
          #   do {
          #     match_byte <<= 1;
          #     const uint32_t match_bit = match_byte & offset;
          #     const uint32_t subcoder_index
          #           = offset + match_bit + (symbol >> 8);
          #     const uint32_t bit = (symbol >> 7) & 1;
          #     rc_bit(rc, &subcoder[subcoder_index], bit);
          #
          #     symbol <<= 1;
          #     offset &= ~(match_byte ^ symbol);
          #
          #   } while (symbol < (UINT32_C(1) << 16));
          # }

          # Calculate base_offset using XZ Utils formula (same as encode_unmatched)
          # (((pos << 8) + prev_byte) & literal_mask) << lc
          context = (((pos << 8) + prev_byte) & literal_mask)
          base_offset = 3 * (context << lc)

          offset = 0x100
          symbol = byte + (1 << 8) # symbol += UINT32_C(1) << 8

          loop do
            # match_byte <<= 1;
            match_byte <<= 1

            # const uint32_t match_bit = match_byte & offset;
            match_bit = match_byte & offset

            # const uint32_t subcoder_index = offset + match_bit + (symbol >> 8);
            subcoder_index = base_offset + offset + match_bit + (symbol >> 8)

            # const uint32_t bit = (symbol >> 7) & 1;
            bit = (symbol >> 7) & 1

            # rc_bit(rc, &subcoder[subcoder_index], bit);
            range_encoder.encode_bit(models[subcoder_index], bit)

            # symbol <<= 1;
            symbol <<= 1

            # offset &= ~(match_byte ^ symbol);
            offset &= ~(match_byte ^ symbol)

            # } while (symbol < (UINT32_C(1) << 16));
            break if symbol >= (1 << 16)
          end
        end

        private

        # Encode remaining bits in unmatched mode
        #
        # Called from matched mode when bits diverge.
        # Similar to encode_unmatched but starts with partial symbol.
        #
        # @param byte [Integer] Original byte value
        # @param symbol [Integer] Partial symbol value
        # @param base_offset [Integer] Model base offset
        # @param range_encoder [RangeEncoder] Range encoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [void]
        def encode_unmatched_tail(byte, symbol, base_offset, range_encoder,
models)
          # Continue encoding remaining bits of the byte
          # symbol contains the bits already encoded (built up from MSB)
          # We need to encode bits from symbol's current position to the end
          remaining_bits = 8 - (symbol.bit_length - 1)
          remaining_bits.times do |i|
            model_index = base_offset + symbol

            # Extract next bit from byte (MSB first from current position)
            bit = (byte >> (7 - i)) & 1

            range_encoder.encode_bit(models[model_index], bit)
            symbol = (symbol << 1) | bit
          end
        end
      end
    end
  end
end
