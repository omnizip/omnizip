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
      # Literal byte decoder
      #
      # This class is responsible for decoding literal bytes using
      # probability models. It supports two modes matching the encoder:
      #
      # 1. Unmatched mode: Simple 8-bit decoding
      # 2. Matched mode: Uses match byte for context (SDK feature)
      #
      # The decoder must perfectly mirror the encoder's decisions
      # about which probability models to use.
      #
      # Single Responsibility: Literal byte decoding only
      #
      # @example Unmatched decoding
      #   decoder = LiteralDecoder.new
      #   byte = decoder.decode_unmatched(lit_state, range_decoder, models)
      #
      # @example Matched decoding (SDK mode)
      #   decoder = LiteralDecoder.new
      #   byte = decoder.decode_matched(match_byte, lit_state, range_decoder, models)
      class LiteralDecoder
        include Constants

        # Decode literal byte in unmatched mode
        #
        # This is the standard LZMA literal decoding where each bit
        # is decoded using probability models based on the partial
        # symbol value.
        #
        # @param lit_state [Integer] Literal context value (0-7 for lc=3, unshifted)
        # @param lc [Integer] Literal context bits (unused, kept for compatibility)
        # @param range_decoder [RangeDecoder] Range decoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [Integer] Decoded byte value (0-255)
        def decode_unmatched(lit_state, lc, range_decoder, models)
          # XZ Utils literal_subcoder returns: probs + 3 * (context_value << lc)
          # where context_value = (((pos << 8) + prev_byte) & literal_mask)
          # Our lit_state is context_value (unshifted)
          # IMPORTANT: Shift BEFORE multiplying by 3 (XZ Utils formula order)
          base_offset = 3 * (lit_state << lc)

          # Start with symbol = 1
          # We build it up bit by bit until it reaches 0x100
          symbol = 1

          # Decode 8 bits to build the symbol from 1 to 0x100
          while symbol < 0x100
            # Model index based on current symbol value
            model_index = base_offset + symbol

            # Decode next bit
            bit = range_decoder.decode_bit(models[model_index])

            # Update symbol: shift left and add bit
            symbol = (symbol << 1) | bit
          end

          # Symbol is now in range 0x100-0x1FF
          # Extract the byte value by subtracting 0x100
          symbol - 0x100
        end

        # Decode literal byte in matched mode (SDK feature)
        #
        # This mode uses a byte from the dictionary (the "match byte")
        # as context for decoding the literal. The decoder must use
        # the same probability model selection as the encoder.
        #
        # SDK algorithm (from LzmaDec.c):
        # - Processes bits in pairs (match bit, literal bit)
        # - Uses match bit to select probability model
        # - Offset updates based on DECODED bit, not match bit (XZ Utils rc_matched_literal)
        # - Switches to unmatched mode when bits diverge
        #
        # @param match_byte [Integer] Corresponding byte from dictionary
        # @param lit_state [Integer] Literal context value (0-7 for lc=3, unshifted)
        # @param lc [Integer] Literal context bits (unused, kept for compatibility)
        # @param range_decoder [RangeDecoder] Range decoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [Integer] Decoded byte value (0-255)
        def decode_matched(match_byte, lit_state, lc, range_decoder, models)
          base_offset = 3 * (lit_state << lc)
          symbol = 1
          # XZ Utils: uint32_t t_match_byte = (match_byte);
          # IMPORTANT: Do NOT OR with 0x100 - start with just match_byte!
          # The offset mechanism handles the bit selection.
          match_sym = match_byte
          # XZ Utils: offset starts at 0x100 and is updated based on DECODED bits
          # See: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_decoder.h:342-357
          offset = 0x100

          # SDK matched literal decoding algorithm
          # Process bits while match byte provides context
          loop do
            # XZ Utils pattern: t_match_byte <<= 1; t_match_bit = t_match_byte & t_offset;
            # IMPORTANT: Shift FIRST, then extract the bit!
            # Shift match symbol (brings next bit into position 8)
            match_sym <<= 1

            # Extract current bit from match symbol
            # XZ Utils: t_match_bit = t_match_byte & t_offset
            # IMPORTANT: This is not just checking if non-zero! The result is used directly:
            # - If the bit is 1: t_match_bit = t_offset (e.g., 0x100)
            # - If the bit is 0: t_match_bit = 0
            # This value is used in model_index calculation AND offset updates
            match_bit = match_sym & offset

            # Calculate model index: XZ Utils formula is t_subcoder_index = t_offset + t_match_bit + symbol
            # where t_offset is updated based on PREVIOUS decoded bit, t_match_bit is from match byte
            model_index = base_offset + offset + match_bit + symbol

            # Decode literal bit
            bit = range_decoder.decode_bit(models[model_index])

            # Update offset based on DECODED bit (XZ Utils pattern)
            # IMPORTANT: XZ Utils rc_bit macro updates symbol BEFORE running the action!
            # So we must update symbol FIRST, then use it for offset calculation.
            # XZ Utils pattern:
            # - bit=0: symbol <<= 1; t_offset &= ~t_match_bit
            # - bit=1: symbol = (symbol << 1) + 1; t_offset &= t_match_bit
            # We can simplify this to:
            # - If bit=0: offset &= ~match_bit
            # - If bit=1: offset &= match_bit

            if bit.zero?
              # Clear the match_bit from offset
              offset &= ~match_bit
              # Update symbol (shift left, add 0)
              symbol <<= 1
            else
              # Keep only the match_bit in offset
              offset &= match_bit
              # Update symbol (shift left, add 1)
              symbol = (symbol << 1) | 1
            end

            # If bits diverge, switch to unmatched mode
            if (match_bit.positive? ? 1 : 0) != bit
              # Continue in unmatched mode for remaining bits
              break if symbol >= 0x100

              return decode_unmatched_tail(symbol, base_offset, lc,
                                           range_decoder, models)
            end

            # Done when symbol reaches 0x100
            break if symbol >= 0x100
          end

          symbol - 0x100
        end

        private

        # Decode remaining bits in unmatched mode
        #
        # Called from matched mode when bits diverge.
        # Similar to decode_unmatched but starts with partial symbol.
        #
        # @param symbol [Integer] Partial symbol value
        # @param base_offset [Integer] Model base offset
        # @param lc [Integer] Literal context bits
        # @param range_decoder [RangeDecoder] Range decoder instance
        # @param models [Array<BitModel>] Literal probability models
        # @return [Integer] Decoded byte value (0-255)
        def decode_unmatched_tail(symbol, base_offset, _lc, range_decoder,
models)
          # Continue building symbol from current value to 0x100
          while symbol < 0x100
            model_index = base_offset + symbol
            bit = range_decoder.decode_bit(models[model_index])
            symbol = (symbol << 1) | bit
          end
          symbol - 0x100
        end
      end
    end
  end
end
