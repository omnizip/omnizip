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

require_relative "xz_match_finder_adapter"
require_relative "xz_encoder_fast"
require_relative "xz_buffered_range_encoder"
require_relative "xz_state"
require_relative "xz_probability_models"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible encoder main
      #
      # Main encoding loop that coordinates all components:
      # - Match finder for finding LZ77 matches
      # - Fast encoder for greedy heuristics
      # - Range encoder for arithmetic coding
      # - State machine and probability models
      #
      # Based on: xz/src/liblzma/lzma/lzma_encoder.c
      class XzEncoder
        include Constants

        attr_reader :output_total

        # Initialize XZ encoder
        #
        # @param options [Hash] Encoding options
        # @option options [Integer] :lc Literal context bits (default 3)
        # @option options [Integer] :lp Literal position bits (default 0)
        # @option options [Integer] :pb Position bits (default 2)
        # @option options [Integer] :nice_len Nice match length (default 32)
        # @option options [Integer] :dict_size Dictionary size (default 8MB)
        def initialize(options = {})
          @lc = options[:lc] || 3
          @lp = options[:lp] || 0
          @pb = options[:pb] || 2
          @nice_len = options[:nice_len] || 32
          @dict_size = options[:dict_size] || (1 << 23) # 8MB default

          @output_total = 0
        end

        # Encode input data to output stream
        #
        # @param input_data [String, Array<Integer>] Input data
        # @param output_stream [IO, StringIO] Output stream
        # @return [Integer] Number of bytes decoder will consume (excludes flush padding)
        def encode(input_data, output_stream)
          # Write LZMA header first (use unknown size to trigger EOS marker)
          write_header(output_stream)

          # Setup components
          setup_components(input_data, output_stream)

          # Main encoding loop
          encode_main_loop

          # Flush encoder
          flush_encoder(output_stream)

          # Return bytes decoder will consume (excludes flush padding for LZMA2 compatibility)
          @fast.bytes_for_decode
        end

        # Write LZMA header to output stream
        #
        # Format (matching XZ Utils lzma_lzma_props_encode):
        # - Property byte: (pb * 5 + lp) * 9 + lc
        # - Dictionary size: 4 bytes little-endian
        # - Uncompressed size: 8 bytes little-endian (0xFFFFFFFFFFFFFFFF for unknown)
        #
        # @param output [IO, StringIO] Output stream
        # @return [void]
        def write_header(output)
          # Property byte: (pb * 5 + lp) * 9 + lc
          props = (((@pb * 5) + @lp) * 9) + @lc
          output.putc(props)

          # Dictionary size (4 bytes little-endian)
          4.times do |i|
            output.putc((@dict_size >> (i * 8)) & 0xFF)
          end

          # Uncompressed size (8 bytes little-endian)
          # Use 0xFFFFFFFFFFFFFFFF for unknown size (standard practice)
          # This allows the encoder to use an EOS marker instead of knowing exact size upfront
          size = 0xFFFFFFFFFFFFFFFF
          8.times do |i|
            output.putc((size >> (i * 8)) & 0xFF)
          end

          # Track header bytes in output_total (1 + 4 + 8 = 13 bytes)
          @output_total += 13
        end

        private

        # Setup all encoding components
        #
        # @param data [String, Array<Integer>] Input data
        # @param output [IO, StringIO] Output stream
        def setup_components(data, output)
          @output_stream = output
          @mf = XzMatchFinderAdapter.new(data, dict_size: @dict_size,
                                               nice_len: @nice_len)
          @encoder = XzBufferedRangeEncoder.new(output)
          @models = XzProbabilityModels.new(@lc, @lp, @pb)
          @state = XzState.new
          @fast = XzEncoderFast.new(@mf, @encoder, @models, @state,
                                    nice_len: @nice_len, lc: @lc, lp: @lp, pb: @pb)
        end

        # Main encoding loop
        def encode_main_loop
          while @mf.available.positive?
            # Encode queued symbols if buffer getting full
            # Keep headroom for largest operation (~30 symbols for match+distance)
            if @encoder.count > 20
              encode_queued_symbols
            end

            # Find best match using fast mode heuristics
            back, len = @fast.find_best_match

            if back == XzEncoderFast::LITERAL_MARKER
              # Encode literal
              encode_literal
            elsif back < XzEncoderFast::REPS
              # Encode rep match (back is rep index 0-3)
              encode_rep(back, len)
            else
              # Encode normal match (back - REPS + 1 is distance)
              encode_match(back - XzEncoderFast::REPS + 1, len)
            end
          end
        end

        # Encode literal at current position
        def encode_literal
          symbol = @mf.current_byte
          @fast.encode_literal(symbol)
          @mf.move_pos
        end

        # Encode rep match
        #
        # @param rep_idx [Integer] Rep index (0-3)
        # @param length [Integer] Match length
        def encode_rep(rep_idx, length)
          @fast.encode_rep_match(rep_idx, length)
          @fast.update_reps_rep(rep_idx)
          @mf.skip(length - 1)
          @mf.move_pos
        end

        # Encode normal match
        #
        # @param distance [Integer] Match distance (0-based)
        # @param length [Integer] Match length
        def encode_match(distance, length)
          @fast.encode_normal_match(distance, length)
          @fast.update_reps_match(distance)
          @mf.skip(length - 1)
          @mf.move_pos
        end

        # Encode queued symbols to output
        def encode_queued_symbols
          return if @encoder.none?

          # Create temporary buffer for encoding
          temp_buffer = "\0" * 10000
          out_pos = IntRef.new(0)

          # Encode symbols to buffer
          @encoder.encode_symbols(temp_buffer, out_pos, 10000)

          # Write to output stream
          if out_pos.value.positive?
            @output_stream.write(temp_buffer[0, out_pos.value])
            @output_total += out_pos.value
          end
        end

        # Flush encoder and write remaining bytes
        #
        # @param output [IO, StringIO] Output stream
        def flush_encoder(output)
          # Encode EOS marker (End of Stream marker) before flush
          # This signals the decoder that the stream is complete
          encode_eos_marker

          # Queue flush operation
          @encoder.queue_flush

          # Encode all remaining queued symbols
          temp_buffer = "\0" * 10000
          out_pos = IntRef.new(0)

          # Encode to buffer
          @encoder.encode_symbols(temp_buffer, out_pos, 10000)

          # Write final bytes
          if out_pos.value.positive?
            slice = temp_buffer[0, out_pos.value]
            output.write(slice)
            @output_total += out_pos.value
          end
        end

        # Encode EOS (End Of Stream) marker
        #
        # The EOS marker is a special match that signals the end of the stream.
        # It's encoded as a normal match with distance = UINT32_MAX (0xFFFFFFFF)
        # and length = MATCH_LEN_MIN (2). The decoder recognizes this as EOS
        # when uncompressed_size == 0xFFFFFFFFFFFFFFFF.
        #
        # Based on: xz/src/liblzma/lzma/lzma_encoder.c
        # @return [void]
        def encode_eos_marker
          # Get position state (use 0 as final position)
          pos_state = 0

          # Encode is_match bit (1 for match)
          prob_is_match = @models.is_match[@state.value][pos_state]
          @encoder.queue_bit(prob_is_match, 1)

          # Encode is_rep bit (0 for normal match, not rep)
          prob_is_rep = @models.is_rep[@state.value]
          @encoder.queue_bit(prob_is_rep, 0)

          # Flush buffer to make room for length encoding
          encode_queued_symbols

          # Encode length (MATCH_LEN_MIN = 2)
          encode_match_length(MATCH_LEN_MIN, pos_state)

          # Flush buffer to make room for distance encoding
          encode_queued_symbols

          # Encode distance (UINT32_MAX = 0xFFFFFFFF)
          encode_distance(0xFFFFFFFF, MATCH_LEN_MIN)
        end

        # Encode match length
        #
        # @param length [Integer] Match length
        # @param pos_state [Integer] Position state
        # @return [void]
        def encode_match_length(length, pos_state)
          len_coder = @models.match_len_encoder
          choice = len_coder.choice

          # Encode choice bit (low vs mid/high)
          if length < MATCH_LEN_MIN + LEN_LOW_SYMBOLS
            # Low lengths
            @encoder.queue_bit(choice, 0)

            # Encode low bittree
            encode_bittree(len_coder.low[pos_state], NUM_LEN_LOW_BITS,
                           length - MATCH_LEN_MIN)
          else
            # Mid or high lengths
            @encoder.queue_bit(choice, 1)

            length -= MATCH_LEN_MIN + LEN_LOW_SYMBOLS
            choice2 = len_coder.choice2

            if length < LEN_MID_SYMBOLS
              # Mid lengths
              @encoder.queue_bit(choice2, 0)

              # Encode mid bittree
              encode_bittree(len_coder.mid[pos_state], NUM_LEN_MID_BITS, length)
            else
              # High lengths
              @encoder.queue_bit(choice2, 1)

              length -= LEN_MID_SYMBOLS

              # Encode high bittree
              encode_bittree(len_coder.high, NUM_LEN_HIGH_BITS, length)
            end
          end
        end

        # Encode distance using slot encoding
        #
        # @param distance [Integer] Distance (0-based)
        # @param length [Integer] Match length (for len_state calculation)
        # @return [void]
        def encode_distance(distance, length)
          dist_slot = get_dist_slot(distance)
          len_state = get_len_to_pos_state(length)

          # Encode distance slot
          encode_bittree(@models.dist_slot[len_state], NUM_DIST_SLOT_BITS,
                         dist_slot)

          # Encode distance footer
          if dist_slot >= START_POS_MODEL_INDEX
            footer_bits = (dist_slot >> 1) - 1
            base = (2 | (dist_slot & 1)) << footer_bits
            dist_reduced = distance - base

            if dist_slot < END_POS_MODEL_INDEX
              # Use probability models
              encode_bittree_reverse(@models.dist_special, dist_reduced, footer_bits,
                                     base - dist_slot)
            else
              # Direct bits + alignment
              direct_bits = footer_bits - DIST_ALIGN_BITS
              @encoder.queue_direct_bits(dist_reduced >> DIST_ALIGN_BITS,
                                         direct_bits)
              encode_bittree_reverse(@models.dist_align, dist_reduced & ((1 << DIST_ALIGN_BITS) - 1),
                                     DIST_ALIGN_BITS, 0)
            end
          end
        end

        # Encode bittree (MSB first)
        #
        # @param probs [Array] Probability models
        # @param num_bits [Integer] Number of bits
        # @param value [Integer] Value to encode
        # @return [void]
        def encode_bittree(probs, num_bits, value)
          context = 1
          num_bits.downto(1) do |i|
            bit = (value >> (i - 1)) & 1
            @encoder.queue_bit(probs[context], bit)
            context = (context << 1) | bit
          end
        end

        # Encode bittree in reverse (LSB first)
        #
        # @param probs [Array] Probability models
        # @param value [Integer] Value to encode
        # @param num_bits [Integer] Number of bits
        # @param offset [Integer] Probability array offset
        # @return [void]
        def encode_bittree_reverse(probs, value, num_bits, offset)
          context = 1
          num_bits.times do |i|
            bit = (value >> i) & 1
            @encoder.queue_bit(probs[offset + context], bit)
            context = (context << 1) | bit
          end
        end

        # Get distance slot for distance
        #
        # @param distance [Integer] Distance (0-based)
        # @return [Integer] Distance slot (0-63)
        def get_dist_slot(distance)
          if distance < NUM_FULL_DISTANCES
            # Use precomputed table for small distances
            distance < 4 ? distance : fast_pos_small(distance)
          else
            # Formula for large distances
            fast_pos_large(distance)
          end
        end

        # Fast position calculation for small distances
        def fast_pos_small(distance)
          # Simplified slot calculation
          slot = 0
          dist = distance
          while dist > 3
            dist >>= 1
            slot += 2
          end
          slot + dist
        end

        # Fast position calculation for large distances
        def fast_pos_large(distance)
          # Find highest bit position
          n = 31
          while n >= 0
            break if (distance >> n) != 0

            n -= 1
          end
          # slot = 2 * n + high_bit
          ((n << 1) + ((distance >> (n - 1)) & 1))
        end

        # Get length state for distance decoding
        #
        # @param length [Integer] Match length
        # @return [Integer] Length state (0-3)
        def get_len_to_pos_state(length)
          if length < NUM_LEN_TO_POS_STATES + MATCH_LEN_MIN
            length - MATCH_LEN_MIN
          else
            NUM_LEN_TO_POS_STATES - 1
          end
        end
      end
    end
  end
end
