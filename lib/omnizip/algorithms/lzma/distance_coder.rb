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
require_relative "bit_model"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # SDK-compatible distance encoder/decoder
      #
      # This class implements the LZMA SDK's distance encoding scheme:
      # - Slot 0-3: Direct encoding (no extra bits)
      # - Slot 4-13: Slot + 1-5 direct bits
      # - Slot 14+: Slot + fixed bits + aligned bits
      #
      # The slot categorizes distances into ranges, and extra bits
      # specify the exact position within that range.
      class DistanceCoder
        include Constants

        # Initialize the distance coder
        #
        # @param num_len_to_pos_states [Integer] Number of length states for slot selection
        def initialize(num_len_to_pos_states)
          @num_len_to_pos_states = num_len_to_pos_states

          # Slot encoders: one per length state, 128 models each
          # Tree needs 2^(num_bits+1) models for a 6-bit tree: indices 1-127
          # This matches the tree decode algorithm which accesses up to index 127
          @slot_encoders = Array.new(num_len_to_pos_states) do
            Array.new(1 << (NUM_DIST_SLOT_BITS + 1)) { BitModel.new }
          end

          # Position encoders for slots 4-13
          @pos_encoders = Array.new(NUM_FULL_DISTANCES - END_POS_MODEL_INDEX) do
            BitModel.new
          end

          # Aligned encoder for slots 14+ (4-bit aligned)
          # Tree needs 2^5 = 32 models for 4-bit tree
          @align_encoder = Array.new(1 << (DIST_ALIGN_BITS + 1)) do
            BitModel.new
          end

          # Precompute distance slot lookup table for fast encoding
          @slot_fast = Array.new(DIST_SLOT_FAST_LIMIT)
          init_slot_fast_table
        end

        # Reset all probability models in place
        #
        # This method resets the bit models to their initial state.
        # Called during state reset to reinitialize probability models.
        #
        # @return [void]
        def reset_models
          if ENV.fetch("DEBUG_RESET_MODELS",
                       nil) && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
            puts "    [DistanceCoder.reset_models] Resetting #{@slot_encoders.size} len_states, each with #{@slot_encoders[0]&.size || '?'} models"
          end
          @slot_encoders.each do |len_state_models|
            len_state_models.each(&:reset)
          end
          @pos_encoders.each(&:reset)
          @align_encoder.each(&:reset)
          if ENV.fetch("DEBUG_RESET_MODELS",
                       nil) && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
            puts "    [DistanceCoder.reset_models] Done resetting"
          end
        end

        # Encode a match distance using SDK-compatible encoding
        #
        # @param range_encoder [RangeEncoder] The range encoder
        # @param distance [Integer] Distance value (already subtracted 1)
        # @param len_state [Integer] Length state for slot selection
        # @return [void]
        def encode(range_encoder, distance, len_state)
          slot = get_dist_slot(distance)

          if ENV["LZMA_DEBUG_ENCODE"]
            puts "[DistanceCoder.encode] distance=#{distance} slot=#{slot} len_state=#{len_state}"
            puts "[DistanceCoder.encode] CALLING encode_tree with symbol=#{slot}"
          end

          # Encode the slot using the appropriate slot encoder
          encode_tree(range_encoder, @slot_encoders[len_state], slot,
                      NUM_DIST_SLOT_BITS)

          # Encode extra bits based on slot
          if slot >= START_POS_MODEL_INDEX
            footer_bits = (slot >> 1) - 1
            base = (2 | (slot & 1)) << footer_bits

            if slot < END_POS_MODEL_INDEX
              # Slots 4-13: Use position encoders (reverse tree encoding)
              encode_reverse_tree(range_encoder,
                                  @pos_encoders,
                                  base - slot - 1,
                                  distance - base,
                                  footer_bits)
            else
              # Slots 14+: Fixed direct bits + aligned bits
              # Encode high bits as direct bits
              range_encoder.encode_direct_bits((distance - base) >> DIST_ALIGN_BITS,
                                               footer_bits - DIST_ALIGN_BITS)

              # Encode low 4 bits using aligned encoder (reverse tree)
              encode_reverse_tree(range_encoder,
                                  @align_encoder,
                                  0,
                                  distance - base,
                                  DIST_ALIGN_BITS)
            end
          end
        end

        # Decode a match distance using SDK-compatible decoding
        #
        # @param range_decoder [RangeDecoder] The range decoder
        # @param len_state [Integer] Length state for slot selection
        # @return [Integer] Decoded distance value (before adding 1)
        def decode(range_decoder, len_state)
          # DEBUG: Trace specific calls to find corruption
          $distance_decode_count ||= 0
          debug_calls = (320..330)
          debug_this = debug_calls.include?($distance_decode_count)
          trace_326 = ($distance_decode_count == 326)
          trace_325 = ($distance_decode_count == 325)

          # DEBUG: Trace large distances (> 100000)
          trace_large = $distance_decode_count.between?(25,
                                                        35) || $distance_decode_count.between?(
                                                          315, 330
                                                        )

          # DEBUG: Trace all when LZMA_DEBUG_DISTANCE is set
          trace_all = ENV.fetch("LZMA_DEBUG_DISTANCE", nil)

          if (trace_325 || trace_large || trace_all) && ENV.fetch(
            "LZMA_DEBUG_DISTANCE", nil
          )
            puts "  [DistanceCoder.decode ##{$distance_decode_count}] START - len_state=#{len_state}"
            puts "    BEFORE: range=#{range_decoder.range.inspect}, code=#{range_decoder.code.inspect}"
          end

          slot = decode_tree(range_decoder, @slot_encoders[len_state],
                             NUM_DIST_SLOT_BITS)

          if (debug_this || trace_large || trace_all) && ENV.fetch(
            "LZMA_DEBUG_DISTANCE", nil
          )
            puts "  [DistanceCoder.decode ##{$distance_decode_count}] len_state=#{len_state}, slot=#{slot}"
            puts "    @slot_encoders[#{len_state}] object_id=#{@slot_encoders[len_state].object_id}"
          end

          # Decode extra bits based on slot
          if slot < START_POS_MODEL_INDEX
            # Slots 0-3: No extra bits
            $distance_decode_count += 1
            if debug_this && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
              puts "    -> distance=#{slot}"
            end
            slot
          else
            footer_bits = (slot >> 1) - 1

            if slot < END_POS_MODEL_INDEX
              # Slots 4-13: Use position encoders (reverse tree decoding)
              base = (2 | (slot & 1)) << footer_bits
              result = base + decode_reverse_tree(range_decoder,
                                                  @pos_encoders,
                                                  base - slot - 1,
                                                  footer_bits)
              $distance_decode_count += 1
              if debug_this && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
                puts "    -> distance=#{result} (slot #{slot})"
              end
            else
              # Slots 14+: Fixed direct bits + aligned bits
              # XZ Utils pattern (lzma_decoder.c:500-514):
              # - Start with rep0 = 2 + (slot & 1)
              # - Decode high_bits using rc_direct (builds up from starting value)
              # - Shift left by ALIGN_BITS
              # - Decode low_bits using aligned encoder
              # - Add symbol (slot) to final result

              footer_bits = (slot >> 1) - 1
              num_direct_bits = footer_bits - DIST_ALIGN_BITS

              # XZ Utils pattern for slot >= 14:
              # rep0 = 2 + (slot & 1)
              # rc_direct(rep0, num_direct_bits)
              # rep0 <<= ALIGN_BITS
              # rc_bittree_rev4(coder->pos_align)
              # IMPORTANT: slot value is NOT added to result
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:507-512
              result = 2 + (slot & 1)

              # Use decode_direct_bits_with_base to match XZ Utils rc_direct
              # rc_direct builds on the base value iteratively
              result = range_decoder.decode_direct_bits_with_base(
                num_direct_bits, result
              )

              # Decode low 4 bits using aligned encoder (reverse tree)
              low_bits = decode_reverse_tree(range_decoder,
                                             @align_encoder,
                                             0,
                                             DIST_ALIGN_BITS)
              if trace_326 && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
                puts "    TRACE_326: low_bits=#{low_bits}"
              end

              # Final result: (result << 4) + low_bits
              # NOTE: slot value is NOT added (XZ Utils pattern - line 513 adds symbol for EOPM check only)
              result = (result << DIST_ALIGN_BITS) + low_bits
              $distance_decode_count += 1
              if (debug_this || trace_large) && ENV.fetch(
                "LZMA_DEBUG_DISTANCE", nil
              )
                puts "    -> slot=#{slot}, result_after_direct=#{result >> DIST_ALIGN_BITS}, low_bits=#{low_bits}, distance=#{result}"
              end
              if result > 100000
                puts "    [LARGE_DISTANCE ##{$distance_decode_count}] distance=#{result}, slot=#{slot}" if ENV["LZMA_DEBUG_DISTANCE"]
                puts "      BEFORE: range_decoder.range=#{range_decoder.range}, range_decoder.code=#{range_decoder.code}" if ENV["LZMA_DEBUG_DISTANCE"]
              end
            end
            result
          end
        end

        private

        # Initialize fast distance slot lookup table
        #
        # @return [void]
        def init_slot_fast_table
          # Fill table based on slot ranges
          # Slot 0: distance 0
          # Slot 1: distance 1
          # Slot 2: distance 2
          # Slot 3: distance 3
          # Slot 4: distances 4-5
          # Slot 5: distances 6-7
          # Slot 6: distances 8-11
          # etc.

          slot = 0
          c = 0

          while slot < NUM_DIST_SLOTS && c < DIST_SLOT_FAST_LIMIT
            # Calculate the start and end of this slot's range
            if slot < 4
              # Slots 0-3 map to single distances
              @slot_fast[c] = slot
              c += 1
              slot += 1
            else
              # Slots 4+ have power-of-2 ranges
              footer_bits = (slot >> 1) - 1
              range_size = 1 << footer_bits

              # Fill this slot's range
              range_size.times do
                break if c >= DIST_SLOT_FAST_LIMIT

                @slot_fast[c] = slot
                c += 1
              end
              slot += 1
            end
          end
        end

        # Get the distance slot for a given distance
        #
        # @param distance [Integer] Distance value
        # @return [Integer] Distance slot (0-63)
        def get_dist_slot(distance)
          if distance < DIST_SLOT_FAST_LIMIT
            @slot_fast[distance]
          else
            # For large distances, calculate slot directly
            # Find the highest bit position
            n = 31
            while n >= 0
              break if (distance >> n) != 0

              n -= 1
            end

            # slot = 2 * n + high_bit
            ((n << 1) + ((distance >> (n - 1)) & 1))
          end
        end

        # Encode a value using a tree of bit models
        #
        # @param range_encoder [RangeEncoder] The range encoder
        # @param models [Array<BitModel>] Array of bit models for the tree
        # @param symbol [Integer] Symbol to encode
        # @param num_bits [Integer] Number of bits in the tree
        # @return [void]
        def encode_tree(range_encoder, models, symbol, num_bits)
          m = 1
          trace_all = ENV.fetch("TRACE_ALL_SLOT_ENCODE", nil)
          iteration = 0

          if trace_all && ENV.fetch("LZMA_DEBUG_ENCODE", nil)
            puts "    [encode_tree START] RECEIVED symbol=#{symbol}, num_bits=#{num_bits}"
            puts "      BEFORE: range=#{range_encoder.range}, low=#{range_encoder.low}"
          end

          (num_bits - 1).downto(0) do |i|
            iteration += 1
            bit = (symbol >> i) & 1
            if trace_all && ENV.fetch("LZMA_DEBUG_ENCODE", nil)
              model_idx = m
              puts "      [#{iteration}/#{num_bits}] i=#{i}, bit=#{bit}, m=#{m}, model_idx=#{model_idx}, prob=#{models[m].probability}"
            end
            range_encoder.encode_bit(models[m], bit)
            m = (m << 1) | bit
          end

          if trace_all && ENV.fetch("LZMA_DEBUG_ENCODE", nil)
            puts "      AFTER: range=#{range_encoder.range}, low=#{range_encoder.low}"
            puts "    [encode_tree END] ENCODED symbol=#{symbol}"
          end
        end

        # Decode a value using a tree of bit models
        #
        # @param range_decoder [RangeDecoder] The range decoder
        # @param models [Array<BitModel>] Array of bit models for the tree
        # @param num_bits [Integer] Number of bits in the tree
        # @return [Integer] Decoded symbol
        def decode_tree(range_decoder, models, num_bits)
          m = 1
          symbol = 0
          trace_this = (num_bits == 6 && ENV.fetch("TRACE_SLOT_DECODE",
                                                   nil)) || ($distance_decode_count == 28)
          trace_all = ENV.fetch("TRACE_ALL_SLOT_DECODE", nil)
          iteration = 0

          if (trace_this || trace_all) && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
            puts "    [decode_tree START] num_bits=#{num_bits}, range=#{range_decoder.range}, code=#{range_decoder.code}"
            puts "      models array object_id=#{models.object_id}"
          end

          (num_bits - 1).downto(0) do |i|
            iteration += 1
            model = models[m]
            bit = range_decoder.decode_bit(model)
            m = (m << 1) | bit
            symbol |= (bit << i)
            if (trace_this || trace_all) && ENV.fetch("LZMA_DEBUG_DISTANCE",
                                                      nil)
              puts "      [#{iteration}/#{num_bits}] i=#{i}, bit=#{bit}, m=#{m}, model.object_id=#{model.object_id}, prob=#{model.probability}, symbol=#{symbol}"
            end
          end
          if (trace_this || trace_all) && ENV.fetch("LZMA_DEBUG_DISTANCE", nil)
            puts "    [decode_tree END] symbol=#{symbol}"
          end
          symbol
        end

        # Encode a value using reverse bit-tree encoding
        #
        # @param range_encoder [RangeEncoder] The range encoder
        # @param models [Array<BitModel>] Array of bit models
        # @param base_idx [Integer] Base index into models array
        # @param symbol [Integer] Symbol to encode
        # @param num_bits [Integer] Number of bits
        # @return [void]
        def encode_reverse_tree(range_encoder, models, base_idx, symbol,
num_bits)
          m = 1
          num_bits.times do |i|
            bit = (symbol >> i) & 1
            range_encoder.encode_bit(models[base_idx + m], bit)
            m = (m << 1) | bit
          end
        end

        # Decode a value using reverse bit-tree decoding
        #
        # @param range_decoder [RangeDecoder] The range decoder
        # @param models [Array<BitModel>] Array of bit models
        # @param base_idx [Integer] Base index into models array
        # @param num_bits [Integer] Number of bits
        # @return [Integer] Decoded symbol
        def decode_reverse_tree(range_decoder, models, base_idx, num_bits)
          m = 1
          symbol = 0
          num_bits.times do |i|
            bit = range_decoder.decode_bit(models[base_idx + m])
            m = (m << 1) | bit
            symbol |= (bit << i)
          end
          symbol
        end
      end
    end
  end
end
