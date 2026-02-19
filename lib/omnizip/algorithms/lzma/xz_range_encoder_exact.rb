# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Direct port of XZ Utils range encoder to Ruby
# Based on: xz/src/liblzma/rangecoder/range_encoder.h

require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible range encoder (direct port)
      #
      # This is a direct port of the XZ Utils range encoder implementation
      # to ensure exact algorithmic compatibility with XZ Utils output.
      class XzRangeEncoder
        include Constants

        # Range encoder constants (matching XZ Utils range_common.h)
        SHIFT_BITS = 8        # RC_SHIFT_BITS
        TOP_BITS = 24         # RC_TOP_BITS
        TOP = 0x01000000      # 2^24
        BIT_MODEL_TOTAL_BITS = 11
        BIT_MODEL_TOTAL = 2048 # 2^11

        # Symbol types (matching XZ Utils enum)
        RC_BIT_0 = 0
        RC_BIT_1 = 1
        RC_DIRECT_0 = 2
        RC_DIRECT_1 = 3
        RC_FLUSH = 4

        # Maximum symbols that can be queued
        RC_SYMBOLS_MAX = 53

        attr_reader :out_total, :count, :low, :range, :cache, :cache_size

        # Initialize the range encoder
        #
        # @param output_stream [IO] The output stream for encoded bytes
        def initialize(output_stream)
          @stream = output_stream
          # Initialize @out_total BEFORE calling reset
          @out_total = 0
          reset
        end

        # Reset encoder to initial state (matches XZ Utils rc_reset)
        def reset
          @low = 0
          @cache_size = 1 # CRITICAL: XZ starts with 1, not 0
          @range = 0xFFFFFFFF
          @cache = 0
          # CRITICAL: Reset @out_total to match XZ Utils behavior (line 63 of range_encoder.h)
          # This ensures bytes_for_decode returns the correct count
          @out_total = 0
          # NOTE: @pre_flush_out_total is NOT reset - it retains its value for bytes_for_decode
          # It will be reset to 0 when a new chunk starts (via initialize)
          @count = 0
          @pos = 0
          @symbols = Array.new(RC_SYMBOLS_MAX, 0)
          @probs = Array.new(RC_SYMBOLS_MAX, nil)
        end

        # Forget pending symbols (matches XZ Utils rc_forget)
        def forget
          raise "Cannot forget while encoding" if @pos != 0

          @count = 0
        end

        # Queue a bit for encoding (matches XZ Utils rc_bit)
        #
        # @param prob [Probability] Probability model
        # @param bit [Integer] Bit value (0 or 1)
        def bit(prob, bit)
          raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

          @symbols[@count] = bit
          @probs[@count] = prob
          @count += 1
        end
        alias queue_bit bit

        # Queue bittree encoding (matches XZ Utils rc_bittree)
        #
        # @param probs [Array<Probability>] Probability array
        # @param bit_count [Integer] Number of bits
        # @param symbol [Integer] Symbol to encode
        def bittree(probs, bit_count, symbol)
          model_index = 1

          bit_count.times do
            bit = (symbol >> (bit_count -= 1)) & 1
            bit(probs[model_index], bit)
            model_index = (model_index << 1) | bit
          end
        end

        # Queue bittree encoding in reverse (matches XZ Utils rc_bittree_reverse)
        #
        # @param probs [Array<Probability>] Probability array
        # @param bit_count [Integer] Number of bits
        # @param symbol [Integer] Symbol to encode
        def bittree_reverse(probs, bit_count, symbol)
          model_index = 1

          bit_count.times do
            bit = symbol & 1
            symbol >>= 1
            bit(probs[model_index], bit)
            model_index = (model_index << 1) | bit
          end
        end

        # Queue direct bits (matches XZ Utils rc_direct)
        #
        # @param value [Integer] Value to encode
        # @param bit_count [Integer] Number of bits
        def direct(value, bit_count)
          bit_count.times do
            raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

            @symbols[@count] = RC_DIRECT_0 | ((value >> (bit_count -= 1)) & 1)
            @probs[@count] = nil
            @count += 1
          end
        end

        # Queue flush operation (matches XZ Utils rc_flush)
        def flush
          puts "[FLUSH] Adding 5 RC_FLUSH symbols, @count before=#{@count}" if ENV["DEBUG"]
          5.times do
            raise "Symbol buffer overflow" if @count >= RC_SYMBOLS_MAX

            @symbols[@count] = RC_FLUSH
            @probs[@count] = nil
            @count += 1
          end
          puts "[FLUSH] @count after=#{@count}" if ENV["DEBUG"]
        end
        alias queue_flush flush

        # Get number of pending bytes (matches XZ Utils rc_pending)
        #
        # @return [Integer] Number of pending output bytes
        def pending
          @cache_size + 5 - 1
        end

        # Check if no symbols are queued
        #
        # @return [Boolean] True if no symbols queued
        def none?
          @count.zero?
        end

        # Encode all queued symbols to output (matches XZ Utils rc_encode)
        #
        # @param out [IO,String] Output buffer
        # @param out_pos [IntegerRef] Current output position
        # @param out_size [Integer] Output buffer size
        # @return [Boolean] True if output buffer filled before encoding complete
        def encode(out, out_pos, out_size)
          raise "Symbol buffer overflow" if @count > RC_SYMBOLS_MAX

          puts "[ENCODE] Start: @count=#{@count} @pos=#{@pos} @out_total=#{@out_total}" if ENV["DEBUG"]

          skip_increment = false

          while @pos < @count
            # Normalize (matches XZ Utils exactly)
            if @range < TOP
              return true if shift_low(out, out_pos, out_size)

              @range <<= SHIFT_BITS
            end

            # Encode current symbol
            case @symbols[@pos]
            when RC_BIT_0
              prob = @probs[@pos]
              # XZ Utils: rc->range = (rc->range >> RC_BIT_MODEL_TOTAL_BITS) * prob
              @range = (@range >> BIT_MODEL_TOTAL_BITS) * prob.value
              # XZ Utils: prob += (RC_BIT_MODEL_TOTAL - prob) >> RC_MOVE_BITS
              prob.value += (BIT_MODEL_TOTAL - prob.value) >> MOVE_BITS
              @probs[@pos] = prob

            when RC_BIT_1
              prob = @probs[@pos]
              # XZ Utils: bound = prob * (rc->range >> RC_BIT_MODEL_TOTAL_BITS)
              bound = prob.value * (@range >> BIT_MODEL_TOTAL_BITS)
              @low += bound
              @range -= bound
              # XZ Utils: prob -= prob >> RC_MOVE_BITS
              prob.value -= prob.value >> MOVE_BITS
              @probs[@pos] = prob

            when RC_DIRECT_0
              @range >>= 1

            when RC_DIRECT_1
              @range >>= 1
              @low += @range

            when RC_FLUSH
              # Prevent further normalizations (XZ Utils behavior)
              @range = 0xFFFFFFFF

              puts "[ENCODE] RC_FLUSH: @pos=#{@pos} @count=#{@count}" if ENV["DEBUG"]

              iteration = 0
              # Flush the last five bytes (see rc_flush)
              begin
                iteration += 1
                puts "[ENCODE] RC_FLUSH iteration #{iteration}: @pos=#{@pos}" if ENV["DEBUG"]
                return true if shift_low(out, out_pos, out_size)

                puts "[ENCODE] After shift_low: @pos=#{@pos}" if ENV["DEBUG"]
              end while (@pos += 1) < @count

              puts "[ENCODE] After RC_FLUSH loop: total #{iteration} iterations" if ENV["DEBUG"]

              # Reset the range encoder (matches XZ Utils)
              reset
              # CRITICAL: Skip the @pos increment at loop end because do-while already did it
              skip_increment = true
              break

            else
              raise "Unknown symbol type: #{@symbols[@pos]}"
            end

            @pos += 1 unless skip_increment
          end

          puts "[ENCODE] End: @count=#{@count} @pos=#{@pos} @out_total=#{@out_total}" if ENV["DEBUG"]

          @count = 0
          @pos = 0

          false
        end

        # Shift low bytes to output (matches XZ Utils rc_shift_low)
        #
        # @param out [IO,String] Output buffer
        # @param out_pos [IntegerRef] Current output position
        # @param out_size [Integer] Output buffer size
        # @return [Boolean] True if output buffer filled
        def shift_low(out, out_pos, out_size)
          # XZ Utils: if ((uint32_t)(rc->low) < (uint32_t)(0xFF000000) || (uint32_t)(rc->low >> 32) != 0)
          if (@low & 0xFFFFFFFF) < 0xFF000000 || (@low >> 32) != 0
            # XZ Utils: do { ... } while (--rc->cache_size != 0);
            while @cache_size.positive?
              return true if out_pos.value == out_size

              # XZ Utils: out[*out_pos] = rc->cache + (uint8_t)(rc->low >> 32)
              output_byte = @cache + ((@low >> 32) & 0xFF)

              if out.is_a?(String)
                out.setbyte(out_pos.value, output_byte)
              else
                out.putc(output_byte)
              end

              out_pos.value += 1
              @out_total += 1
              @cache = 0xFF

              @cache_size -= 1
            end

            # XZ Utils: rc->cache = (rc->low >> 24) & 0xFF
            @cache = (@low >> 24) & 0xFF
          end

          # XZ Utils: ++rc->cache_size; rc->low = (rc->low & 0x00FFFFFF) << RC_SHIFT_BITS
          @cache_size += 1
          @low = (@low & 0x00FFFFFF) << SHIFT_BITS

          false
        end

        # Adapter method: alias for bit (to match existing API)
        alias queue_bit bit

        # Adapter method: alias for bittree (to match existing API)
        alias queue_bittree bittree

        # Adapter method: alias for bittree_reverse (to match existing API)
        alias queue_bittree_reverse bittree_reverse

        # Adapter method: alias for direct (to match existing API)
        def queue_direct_bits(value, num_bits)
          direct(value, num_bits)
        end

        # Adapter method: alias for encode (to match existing API)
        alias encode_symbols encode

        # Adapter method: match existing API
        alias queue_flush flush

        # Forget pending symbols (matches XZ Utils rc_forget)
        def forget
          raise "Cannot forget while encoding" if @pos != 0

          @count = 0
        end

        # Calculate pending output bytes
        #
        # @return [Integer] Number of bytes decoder will consume
        def bytes_for_decode
          @out_total
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
