# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

require_relative "range_coder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible buffered range encoder
      #
      # This encoder queues symbols for deferred encoding, matching
      # XZ Utils' architecture. This enables:
      # - Price calculation without actual encoding
      # - Optimal parsing with lookahead
      # - Output size limiting for LZMA2
      #
      # Based on: xz/src/liblzma/rangecoder/range_encoder.h
      class XzBufferedRangeEncoder < RangeCoder
        # Symbol types (matching XZ Utils enum)
        RC_BIT_0 = :bit_0
        RC_BIT_1 = :bit_1
        RC_DIRECT_0 = :direct_0
        RC_DIRECT_1 = :direct_1
        RC_FLUSH = :flush

        # Maximum symbols that can be queued
        RC_SYMBOLS_MAX = 53

        # Symbol queue entry
        SymbolEntry = Struct.new(:type, :prob, keyword_init: true)

        # Mutable probability model for XZ Utils encoder
        # Unlike BitModel, this has a mutable value attribute for inline updates
        class Probability
          include Constants

          attr_accessor :value

          def initialize(initial_value = BIT_MODEL_TOTAL >> 1)
            @value = initial_value
          end

          # Update the probability model based on an actual bit value
          # Compatibility with BitModel interface
          def update(bit)
            if bit.zero?
              @value += ((BIT_MODEL_TOTAL - @value) >> MOVE_BITS)
            else
              @value -= (@value >> MOVE_BITS)
            end
          end

          # Compatibility with BitModel interface
          alias probability value
        end

        attr_reader :out_total, :count

        # Return bytes needed for decoding
        #
        # @return [Integer] Number of bytes decoder will consume
        def bytes_for_decode
          @out_total
        end

        # Initialize buffered range encoder
        #
        # @param output_stream [IO] The output stream for encoded bytes
        def initialize(output_stream)
          super
          @cache = 0
          @cache_size = 1 # XZ starts with 1, not 0
          @out_total = 0

          # Symbol queue
          @symbols = []
          @probs = []
          @count = 0
          @pos = 0
        end

        # Reset encoder to initial state
        # NOTE: @out_total is NOT reset here - it tracks cumulative output across chunks
        # and should only be initialized in initialize()
        def reset
          @low = 0
          @cache_size = 1
          @range = 0xFFFFFFFF
          @cache = 0
          @count = 0
          @pos = 0
          @symbols.clear
          @probs.clear
        end

        # Queue a bit for encoding (deferred)
        #
        # @param prob [BitModel] Probability model
        # @param bit [Integer] Bit value (0 or 1)
        def queue_bit(prob, bit)
          raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

          @symbols[@count] = bit.zero? ? RC_BIT_0 : RC_BIT_1
          @probs[@count] = prob
          @count += 1
        end

        # Queue direct bits for encoding (deferred)
        #
        # @param value [Integer] Value to encode
        # @param num_bits [Integer] Number of bits
        def queue_direct_bits(value, num_bits)
          num_bits.downto(1) do |i|
            bit = (value >> (i - 1)) & 1
            raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

            @symbols[@count] = bit.zero? ? RC_DIRECT_0 : RC_DIRECT_1
            @probs[@count] = nil
            @count += 1
          end
        end

        # Queue flush operation
        def queue_flush
          5.times do
            raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

            @symbols[@count] = RC_FLUSH
            @probs[@count] = nil
            @count += 1
          end
        end

        # Encode all queued symbols to output
        #
        # @param out [IO,String] Output buffer
        # @param out_pos [Integer] Current output position
        # @param out_size [Integer] Output buffer size
        # @return [Boolean] True if output buffer filled before encoding complete
        def encode_symbols(out, out_pos, out_size)
          while @pos < @count
            symbol = @symbols[@pos]

            # Check if this is a flush symbol BEFORE normalization
            is_flush = (symbol == RC_FLUSH)

            # Normalize if range too small (skip during flush mode)
            # Important: normalization may need multiple iterations and buffer fills
            while @range < TOP && !is_flush
              # Try to write a byte
              if shift_low_buffered(out, out_pos, out_size)
                # Buffer full - update range anyway so we make progress on next call
                @range <<= 8
                return true
              end

              # Successfully shifted, update range
              @range <<= 8
            end

            # Track whether we should increment @pos after the case statement
            increment_pos = true

            # Encode current symbol
            case symbol
            when RC_BIT_0
              prob = @probs[@pos]
              bound = (@range >> 11) * prob.value

              @range = bound
              # XZ Utils inline probability update for bit=0
              prob.value += (BIT_MODEL_TOTAL - prob.value) >> MOVE_BITS
            when RC_BIT_1
              prob = @probs[@pos]
              bound = (@range >> 11) * prob.value

              @low += bound
              @range -= bound
              # XZ Utils inline probability update for bit=1
              prob.value -= prob.value >> MOVE_BITS
            when RC_DIRECT_0
              # Direct bit 0: @range >>= 1 (matches XZ Utils rc_direct pattern where dest += 0)
              @range >>= 1
            when RC_DIRECT_1
              # Direct bit 1: @range >>= 1; @low += @range (matches XZ Utils rc_direct pattern)
              @range >>= 1
              @low += @range
            when RC_FLUSH
              # Prevent further normalization (XZ Utils sets range to UINT32_MAX)
              @range = 0xFFFFFFFF

              # CRITICAL: XZ Utils processes ALL remaining flush symbols in a tight loop
              # before resetting. The loop does: do { rc_shift_low } while (++rc->pos < rc->count)
              # This means it processes the current flush symbol, increments pos, then
              # checks if there are more symbols to process.
              loop do
                # XZ Utils behavior: when low=0 and cache=0, no useful bytes can be written
                # We consume the RC_FLUSH symbol but don't write output
                # After writing cache+carry, if no new cache value and cache_size=0, we're done
                low32 = @low & 0xFFFFFFFF
                high = @low >> 32
                (low32 >> 24) & 0xFF

                # If low and cache are both zero, and cache_size is 0 or 1, we're done
                # (cache_size will be 1 after setting new_cache, or 0 if it was 0 and new_cache is 0)
                break if low32.zero? && high.zero? && @cache.zero? && @cache_size <= 1

                # Process this flush symbol (write one byte)
                if shift_low_buffered(out, out_pos, out_size)
                  # Buffer full - pause and resume later
                  return true
                end

                # Increment position (matches ++rc->pos in XZ Utils)
                @pos += 1

                # Check if we should continue (matches ++rc->pos < rc->count in XZ Utils)
                # Continue while there are more symbols AND the next symbol is also RC_FLUSH
                break unless @pos < @count && @symbols[@pos] == RC_FLUSH
              end

              # After all flush symbols processed, reset encoder state (like XZ Utils)
              reset
              @count = 0
              # Don't increment @pos again - it was already incremented in the loop
              increment_pos = false
            end

            # Increment position for non-flush symbols (flush symbols increment in the loop)
            @pos += 1 if increment_pos
          end

          # All symbols encoded (flush returns early with @count = 0)
          @count = 0
          @pos = 0
          false
        end

        # Forget queued symbols (e.g., when output limit reached)
        def forget
          raise "Cannot forget with partial encoding" unless @pos.zero?

          @count = 0
        end

        # Get number of pending output bytes
        #
        # @return [Integer] Pending bytes count
        def pending
          @cache_size + 5 - 1
        end

        # Check if there are no queued symbols
        #
        # @return [Boolean] True if no symbols queued
        def none?
          @count.zero?
        end

        private

        # Shift low byte to output (buffered version)
        #
        # @param out [IO,String] Output buffer
        # @param out_pos [Ref<Integer>] Current output position (modified)
        # @param out_size [Integer] Output buffer size
        # @return [Boolean] True if buffer full
        def shift_low_buffered(out, out_pos, out_size)
          low32 = @low & 0xFFFFFFFF
          high = @low >> 32

          # During flush mode, force output of cache byte even if cache_size=0
          flush_mode = (@range == 0xFFFFFFFF)

          # XZ Utils: Write bytes if low32 < 0xFF000000 OR high != 0
          # During flush mode, ALWAYS write at least one byte
          if low32 < 0xFF000000 || high != 0 || flush_mode
            # Output cache + carry, then pending 0xFF bytes
            # In flush mode, write at least one byte (the cache)
            loop_count = flush_mode && @cache_size.zero? ? 1 : @cache_size

            while loop_count.positive?
              if out_pos.value >= out_size
                return true
              end

              output_byte = (@cache + high) & 0xFF

              if out.is_a?(String)
                out.setbyte(out_pos.value, output_byte)
              else
                out.putc(output_byte)
              end
              out_pos.value += 1
              @out_total += 1

              @cache = 0xFF # Set cache to 0xFF for pending bytes

              loop_count -= 1
              @cache_size -= 1 if @cache_size.positive?
            end

            @cache = (low32 >> 24) & 0xFF
          end

          # XZ Utils: ALWAYS increment cache_size, even during flush mode
          # This is critical for correct encoder behavior
          @cache_size += 1
          @low = (low32 << 8) & 0xFFFFFFFF
          false
        end
      end

      # Reference wrapper for integer (for out_pos parameter)
      class IntRef
        attr_accessor :value

        def initialize(val)
          @value = val
        end
      end
    end
  end
end
