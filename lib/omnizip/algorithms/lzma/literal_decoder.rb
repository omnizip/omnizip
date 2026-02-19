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

          # TEMP DEBUG: Trace first literal decode
          if ENV["TRACE_LITERAL_DECODE"] && lit_state.zero?
            # range = range_decoder.instance_variable_get(:@range)
            # code = range_decoder.instance_variable_get(:@code)
            # puts ""
            # puts "=== decode_unmatched START: lit_state=#{lit_state}, base_offset=#{base_offset} ==="
            # puts "Initial: range=0x#{range.to_s(16)}, code=0x#{code.to_s(16)}"
          end

          # DEBUG: Trace lit_state=96 (the corrupted literal)
          if lit_state == 96
            # range = range_decoder.instance_variable_get(:@range)
            # code = range_decoder.instance_variable_get(:@code)
            # puts ""
            # puts "=== decode_unmatched START: lit_state=#{lit_state}, base_offset=#{base_offset} ==="
            # puts "Initial: range=0x#{range.to_s(16)}, code=0x#{code.to_s(16)}"
          end

          # Decode 8 bits to build the symbol from 1 to 0x100
          while symbol < 0x100
            # Model index based on current symbol value
            model_index = base_offset + symbol

            # Decode next bit
            bit = range_decoder.decode_bit(models[model_index])

            if ENV["TRACE_LITERAL_DECODE"] && lit_state.zero?
              range_after = range_decoder.instance_variable_get(:@range)
              code_after = range_decoder.instance_variable_get(:@code)
              puts "Bit #{symbol}: model_index=#{model_index}, bit=#{bit}, range=0x#{range_after.to_s(16)}, code=0x#{code_after.to_s(16)}" if ENV["LZMA_DEBUG_BITS"]
            end

            # DEBUG: Trace bits for lit_state=96
            if ENV["LZMA_DEBUG_BITS"] && lit_state == 96
              range_after = range_decoder.instance_variable_get(:@range)
              code_after = range_decoder.instance_variable_get(:@code)
              puts "  symbol=#{symbol}: model_index=#{model_index}, bit=#{bit}, range=0x#{range_after.to_s(16)}, code=0x#{code_after.to_s(16)}"
            end

            # Update symbol: shift left and add bit
            symbol = (symbol << 1) | bit
          end

          # Symbol is now in range 0x100-0x1FF
          # Extract the byte value by subtracting 0x100
          result = symbol - 0x100

          if ENV["TRACE_LITERAL_DECODE"] && lit_state.zero?
            puts "Result: 0x#{result.to_s(16)} ('#{result.chr}')"
            puts "=== decode_unmatched END ==="
            puts ""
          end

          result
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

          # DEBUG: Trace matched literal decode at position 61
          if ENV["TRACE_MATCHED_DECODE"] && lit_state == 96
            puts "=== MATCHED LITERAL DECODE: lit_state=#{lit_state}, match_byte=0x#{match_byte.to_s(16).upcase} ==="
            puts "  base_offset=#{base_offset}"
            puts "  Initial: symbol=#{symbol}, offset=0x#{offset.to_s(16).upcase}"
          end

          # SDK matched literal decoding algorithm
          # Process bits while match byte provides context
          bit_num = 0
          result_bits = [] # DEBUG: Track decoded bits

          # DEBUG: Trace at dict_full=233
          trace_233 = ENV.fetch("DICT_FULL_233_TRACE", nil) && lit_state.zero?

          if trace_233
            puts "=== MATCHED LITERAL TRACE at dict_full=233 ==="
            puts "  match_byte=0x#{match_byte.to_s(16).upcase}"
            puts "  base_offset=#{base_offset}"
            puts "  Initial: symbol=#{symbol}, offset=0x#{offset.to_s(16).upcase}"
          end

          loop do
            if trace_233
              puts "\n  Bit #{bit_num}:"
              puts "    match_sym=0x#{(match_sym & 0xFF).to_s(16).upcase}, offset=0x#{offset.to_s(16).upcase}"
            end

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

            if trace_233
              puts "    match_bit=0x#{match_bit.to_s(16).upcase}, symbol=#{symbol}"
              puts "    model_index=#{model_index}"
              puts "    offset_from_base=#{model_index - base_offset}"
              prob_before = models[model_index].probability
              puts "    probability_before=0x#{prob_before.to_s(16).upcase} (#{prob_before})"
              # Trace range decoder state BEFORE decode_bit
              rd_range_before = range_decoder.instance_variable_get(:@range)
              rd_code_before = range_decoder.instance_variable_get(:@code)
              puts "    range_decoder BEFORE: range=0x#{rd_range_before.to_s(16)}, code=0x#{rd_code_before.to_s(16)}"
            end

            # Decode literal bit
            bit = range_decoder.decode_bit(models[model_index])
            result_bits << bit # DEBUG: Track bit

            if trace_233
              prob_after = models[model_index].probability
              puts "    decoded_bit=#{bit}"
              puts "    probability_after=0x#{prob_after.to_s(16).upcase} (#{prob_after})"
              # Also trace the range decoder state after decode_bit
              rd_range = range_decoder.instance_variable_get(:@range)
              rd_code = range_decoder.instance_variable_get(:@code)
              puts "    range_decoder AFTER: range=0x#{rd_range.to_s(16)}, code=0x#{rd_code.to_s(16)}"
            end

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

            if ENV["TRACE_MATCHED_DECODE"] && lit_state == 96
              puts "    new_offset=0x#{offset.to_s(16).upcase}"
              puts "    new_symbol=#{symbol} (0x#{symbol.to_s(16).upcase})"
            end

            # If bits diverge, switch to unmatched mode
            if (match_bit.positive? ? 1 : 0) != bit
              if ENV["TRACE_MATCHED_DECODE"] && lit_state == 96
                puts "    *** BITS DIVERGE - switching to unmatched mode ***"
              end
              if trace_233
                puts "    *** BITS DIVERGE at bit #{bit_num} - match_bit=#{match_bit.positive? ? 1 : 0}, decoded_bit=#{bit} ***"
              end
              # Continue in unmatched mode for remaining bits
              break if symbol >= 0x100

              result = decode_unmatched_tail(symbol, base_offset, lc, range_decoder,
                                             models)
              if trace_233
                puts "\n  FINAL RESULT (after unmatched tail): 0x#{result.to_s(16).upcase} ('#{result.chr}')"
                puts "  Result bits: #{result_bits.join}"
                puts "=== END MATCHED LITERAL TRACE ===\n"
              end
              return result
            end

            # Done when symbol reaches 0x100
            break if symbol >= 0x100

            bit_num += 1
          end

          result = symbol - 0x100
          if trace_233 || (ENV.fetch("TRACE_MATCHED_DECODE", nil) && lit_state == 96)
            puts "\n  FINAL RESULT: 0x#{result.to_s(16).upcase} ('#{result.chr}')"
            if trace_233
              puts "  Result bits: #{result_bits.join}"
            end
            puts "=== END MATCHED LITERAL DECODE ===\n"
          end
          result
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
