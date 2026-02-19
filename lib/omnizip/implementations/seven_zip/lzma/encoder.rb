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

require_relative "../../../algorithms/lzma/constants"
require_relative "match_finder"
require_relative "../../../algorithms/lzma/match_finder_config"
require_relative "../../../algorithms/lzma/match_finder_factory"
require_relative "../../../algorithms/lzma/literal_encoder"
require_relative "state_machine"
require_relative "../../../algorithms/lzma/length_coder"
require_relative "../../../algorithms/lzma/distance_coder"
require_relative "range_encoder" # Use 7-Zip SDK range encoder (not XZ Utils)
require_relative "../../../algorithms/lzma/bit_model"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # 7-Zip LZMA SDK encoder implementation.
        #
        # This is the original SdkEncoder moved from algorithms/lzma/sdk_encoder.rb
        # to the new namespace structure.
        #
        # Ported from 7-Zip LZMA SDK by Igor Pavlov.
        class Encoder
          include Omnizip::Algorithms::LZMA::Constants

          attr_reader :lc, :lp, :pb, :dict_size

          # Initialize the SDK-compatible encoder
          #
          # @param output [IO] Output stream for compressed data
          # @param options [Hash] Encoding options
          # @option options [Integer] :lc Literal context bits (0-8, default: 3)
          # @option options [Integer] :lp Literal position bits (0-4, default: 0)
          # @option options [Integer] :pb Position bits (0-4, default: 2)
          # @option options [Integer] :dict_size Dictionary size (default: 64KB)
          # @option options [Integer] :level Compression level (0-9, default: 5)
          # @option options [Boolean] :raw_mode Skip header and EOS marker for LZMA2 (default: false)
          def initialize(output, options = {})
            @output = output
            @lc = options.fetch(:lc, 3)
            @lp = options.fetch(:lp, 0)
            @pb = options.fetch(:pb, 2)
            @dict_size = options.fetch(:dict_size, 1 << 16) # 64KB default
            @level = options.fetch(:level, 5)
            @raw_mode = options.fetch(:raw_mode, false) # NEW: skip header/EOS for LZMA2

            validate_parameters
            init_models
            init_coders
          end

          # Encode a stream of data
          #
          # Main encoding loop following SDK's LzmaEnc_CodeOneBlock logic:
          # 1. Initialize match finder with data
          # 2. Process each position: find matches, encode literals/matches
          # 3. Write EOS marker
          # 4. Flush range encoder
          #
          # @param data [String, IO] Input data to compress
          # @return [Array<String, Integer>] Tuple of [compressed_data, decode_bytes]
          def encode_stream(data)
            input_data = data.is_a?(String) ? data : data.read

            # Force binary encoding to handle binary data properly
            # Duplicate to avoid modifying frozen strings
            input_data = input_data.dup.force_encoding(Encoding::BINARY)

            # Write LZMA header
            write_header(input_data.bytesize) unless @raw_mode

            # Initialize range encoder (7-Zip SDK version)
            @range_encoder = RangeEncoder.new(@output)

            # Initialize match finder with SDK configuration
            match_finder_config = Omnizip::Algorithms::LZMA::MatchFinderConfig.sdk_config(
              dict_size: @dict_size,
              level: @level,
            )
            @match_finder = Omnizip::Algorithms::LZMA::MatchFinderFactory.create(match_finder_config)

            # Initialize state and dictionary
            @state = StateMachine.new
            @dict = +"" # Mutable string for dictionary
            @pos = 0

            # Initialize repeat distances (all 1 initially, as in SDK)
            @reps = [1, 1, 1, 1]

            # Main encoding loop
            while @pos < input_data.bytesize
              # Find best match at current position
              match = @match_finder.find_longest_match(input_data, @pos)

              # Decide: literal vs match
              if should_encode_match?(match)
                encode_match(match, input_data)
              else
                encode_literal(input_data[@pos].ord, input_data)
              end
            end

            # Write EOS marker and flush
            # For LZMA2: skip EOS marker but DO flush the range encoder
            # The range encoder flush outputs pending bytes needed by decoder
            # LZMA2 uses CONTROL_END (0x00) to signal end of stream instead of LZMA EOS
            encode_eos_marker unless @raw_mode # Skip EOS in raw mode
            @range_encoder.flush # Always flush to output pending range encoder bytes

            # Return tuple for LZMA2: [data, bytes_for_decode]
            # For raw mode, return actual decode bytes (excluding flush padding)
            if @raw_mode
              [@output.string, @range_encoder.bytes_for_decode]
            elsif @output.respond_to?(:string)
              # For File output, just return bytes written (don't try to read back)
              # For StringIO, return the string and its size
              [@output.string, @output.string.bytesize]
            else
              [@range_encoder.bytes_for_decode, @range_encoder.bytes_for_decode]
            end
          end

          private

          # Validate encoding parameters
          #
          # @return [void]
          # @raise [ArgumentError] If parameters are invalid
          def validate_parameters
            raise ArgumentError, "lc must be 0-8" unless @lc.between?(0, 8)
            raise ArgumentError, "lp must be 0-4" unless @lp.between?(0, 4)
            raise ArgumentError, "pb must be 0-4" unless @pb.between?(0, 4)
            raise ArgumentError, "level must be 0-9" unless @level.between?(0, 9)
            return if @dict_size.between?(DICT_SIZE_MIN, DICT_SIZE_MAX)

            raise ArgumentError, "Invalid dictionary size"
          end

          # Initialize probability models
          #
          # SDK allocates models following exact structure from LzmaEnc.c:
          # - Literal models: compact layout indexed by literal_subcoder macro
          # - Match models: NUM_STATES * (1 << @pb) models
          # - Rep models: NUM_STATES models each
          #
          # The literal_subcoder macro calculates:
          #   base_offset = 3 * (((((pos) << 8) + (prev_byte)) & (literal_mask)) << (lc))
          # We need to allocate enough models for the maximum possible offset.
          #
          # @return [void]
          def init_models
            # Calculate literal_mask using XZ Utils formula
            # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
            literal_mask = (0x100 << @lp) - (0x100 >> @lc)

            # Calculate maximum possible context value
            # context = (((pos << 8) + prev_byte) & literal_mask)
            # Maximum context occurs when the lower bits of (pos << 8) + prev_byte
            # align with the mask to give the maximum value.
            max_context = literal_mask # Maximum possible context value

            # Calculate maximum base_offset
            # base_offset = 3 * (context << lc)
            max_base_offset = 3 * (max_context << @lc)

            # Maximum index for matched mode:
            # encode_matched can use up to base_offset + offset + match_bit + (symbol >> 8)
            # where offset, match_bit, and (symbol >> 8) can each be up to 0x100
            # So max index = base_offset + 0x100 + 0x100 + 0x100 = base_offset + 0x300
            # encode_unmatched can use up to base_offset + 256
            max_model_index = max_base_offset + 0x300

            # Allocate literal models
            @literal_models = Array.new(max_model_index + 1) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end

            # Match/rep decision models
            @is_match_models = Array.new(NUM_STATES * (1 << @pb)) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep_models = Array.new(NUM_STATES) { Omnizip::Algorithms::LZMA::BitModel.new }
            @is_rep0_models = Array.new(NUM_STATES) { Omnizip::Algorithms::LZMA::BitModel.new }
            @is_rep1_models = Array.new(NUM_STATES) { Omnizip::Algorithms::LZMA::BitModel.new }
            @is_rep2_models = Array.new(NUM_STATES) { Omnizip::Algorithms::LZMA::BitModel.new }
            @is_rep0_long_models = Array.new(NUM_STATES * (1 << @pb)) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
          end

          # Initialize SDK coders
          #
          # @return [void]
          def init_coders
            @literal_encoder = Omnizip::Algorithms::LZMA::LiteralEncoder.new(@lc)
            @length_coder = Omnizip::Algorithms::LZMA::LengthCoder.new(1 << @pb)
            @rep_length_coder = Omnizip::Algorithms::LZMA::LengthCoder.new(1 << @pb)
            @distance_coder = Omnizip::Algorithms::LZMA::DistanceCoder.new(NUM_LEN_TO_POS_STATES)
          end

          # Determine if a match should be encoded
          #
          # SDK uses complex heuristics considering:
          # - Match length vs literal cost
          # - Position in stream
          # - Previous encoding results
          #
          # Simplified heuristic: encode if length >= 2 and provides benefit
          #
          # @param match [MatchFinder::Match, nil] Found match
          # @return [Boolean] True if match should be encoded
          def should_encode_match?(match)
            return false if match.nil?
            return false if match.length < MATCH_LEN_MIN

            # CRITICAL: Validate that match distance is within current position
            # The decoder reads from its dictionary: src_pos = dict_pos - distance - 1
            # We need src_pos >= 0, which means distance <= dict_pos (current position)
            # The match finder may return distances up to window_size, but we can only
            # encode distances that reference data we've already encoded
            return false if match.distance > @pos

            # Simple heuristic: encode matches length >= 2
            # For length 2: only if distance is small (< 128)
            # For length 3+: always encode
            if match.length == 2
              match.distance < 128
            else
              true
            end
          end

          # Encode a literal byte
          #
          # SDK encoding sequence (from LzmaEnc.c):
          # 1. Encode is_match bit (0 = literal)
          # 2. Calculate literal state
          # 3. Encode literal (matched or unmatched based on state)
          # 4. Update state machine
          # 5. Update dictionary and position
          #
          # @param byte [Integer] Byte to encode (0-255)
          # @param data [String] Full input data (for context)
          # @return [void]
          def encode_literal(byte, _data)
            pos_state = @pos & ((1 << @pb) - 1)

            # Encode is_match bit (0 = literal)
            # XZ Utils: is_match[state][pos_state] where the array size is NUM_STATES * (1 << pb)
            model_index = (@state.value * (1 << @pb)) + pos_state
            @range_encoder.encode_bit(@is_match_models[model_index], 0)

            # Calculate previous byte for literal encoding
            # XZ Utils dict_get0 pattern: dict->buf[dict->pos - 1]
            prev_byte = @dict.bytesize.positive? ? @dict[-1].ord : 0

            # Calculate literal_mask using XZ Utils formula
            # From lzma_common.h:literal_mask_calc
            # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
            literal_mask = (0x100 << @lp) - (0x100 >> @lc)

            # Encode literal (matched or unmatched)
            # Check if we can use matched literal: need enough data at current position
            # The match is at dict[pos - reps[0] - 1], so we need pos > reps[0]
            if @state.use_matched_literal? && @pos > @reps[0]
              # Matched literal: use match byte from repeat distance
              # The decoder uses get_byte_from_dict(reps[0]) which is dict[dict_pos - reps[0]]
              # We need to use the same formula: dict[pos - reps[0]]
              # Note: This is different from the SDK formula which uses -1
              match_byte = @dict[@pos - @reps[0]].ord
              @literal_encoder.encode_matched(byte, match_byte, @pos, prev_byte,
                                              @lc, literal_mask, @range_encoder, @literal_models)
            else
              # Unmatched literal: simple 8-bit encoding
              @literal_encoder.encode_unmatched(byte, @pos, prev_byte,
                                                @lc, literal_mask, @range_encoder, @literal_models)
            end

            # Update state and dictionary
            @state.update_literal
            @dict << byte.chr
            @pos += 1
          end

          # Encode a match
          #
          # SDK encoding sequence:
          # 1. Encode is_match bit (1 = match)
          # 2. Encode is_rep bit (0 = regular match)
          # 3. Encode match length using length coder
          # 4. Encode match distance using distance coder
          # 5. Update state machine
          # 6. Update dictionary and position
          #
          # @param match [MatchFinder::Match] Match to encode
          # @param data [String] Full input data (for updating dictionary)
          # @return [void]
          def encode_match(match, data)
            # Defensive check: distance must be >= 1
            raise "Invalid match distance: #{match.distance}" if match.distance < 1

            pos_state = @pos & ((1 << @pb) - 1)

            # Encode is_match bit (1 = match)
            # XZ Utils: is_match[state][pos_state] where the array is NUM_STATES * (1 << @pb)
            model_index = (@state.value * (1 << @pb)) + pos_state
            @range_encoder.encode_bit(@is_match_models[model_index], 1)

            # Encode is_rep bit (0 = regular match, not rep)
            # For now, we only handle regular matches
            @range_encoder.encode_bit(@is_rep_models[@state.value], 0)

            # Calculate length state for distance encoding
            # XZ Utils formula (from lzma_common.h get_dist_state macro):
            # ((len) < DIST_STATES + MATCH_LEN_MIN ? (len) - MATCH_LEN_MIN : DIST_STATES - 1)
            # This gives: len=2→0, len=3→1, len=4→2, len=5→3, len=6+→3
            len_state = if match.length < NUM_LEN_TO_POS_STATES + MATCH_LEN_MIN
                          match.length - MATCH_LEN_MIN
                        else
                          NUM_LEN_TO_POS_STATES - 1
                        end

            # Encode match length
            @length_coder.encode(@range_encoder,
                                 match.length - MATCH_LEN_MIN,
                                 pos_state)

            # Encode match distance
            # Distance coder expects (distance - 1), decoder will add 1 back
            @distance_coder.encode(@range_encoder,
                                   match.distance - 1,
                                   len_state)

            # Update repeat distances (shift and add new distance)
            # When encoding a regular match, the distance becomes the new rep0
            @reps[3] = @reps[2]
            @reps[2] = @reps[1]
            @reps[1] = @reps[0]
            @reps[0] = match.distance

            # Update state
            @state.update_match

            # Update dictionary with matched data
            matched_data = data[@pos, match.length]
            @dict << matched_data
            @pos += match.length
          end

          # Encode end-of-stream marker
          #
          # SDK EOS marker (from LzmaEnc.c):
          # - Encoded as a match with maximum distance
          # - Signals decoder to stop
          #
          # @return [void]
          def encode_eos_marker
            # Use actual position state, not hardcoded 0
            pos_state = @pos & ((1 << @pb) - 1)

            # Encode is_match bit (1 = match)
            # XZ Utils: is_match[state][pos_state] where the array is NUM_STATES * (1 << @pb)
            model_index = (@state.value * (1 << @pb)) + pos_state
            @range_encoder.encode_bit(@is_match_models[model_index], 1)

            # Encode is_rep bit (0 = regular match)
            @range_encoder.encode_bit(@is_rep_models[@state.value], 0)

            # Calculate len_state to match decoder's calculation
            # Decoder: length = decoded_value + MATCH_LEN_MIN = 0 + 2 = 2
            # len_state = 2 - MATCH_LEN_MIN = 0 (when 2 < 4)
            len_state = 0 # MATCH_LEN_MIN - MATCH_LEN_MIN

            # Encode minimum length (0, decoder adds MATCH_LEN_MIN to get 2)
            @length_coder.encode(@range_encoder, 0, pos_state)

            # Encode special EOS distance (0xFFFFFFFF)
            # XZ Utils encode_eopm calls match(coder, pos_state, UINT32_MAX, MATCH_LEN_MIN)
            # Decoder adds 1 to get distance = 0x100000000, which triggers EOS check
            @distance_coder.encode(@range_encoder, 0xFFFFFFFF, len_state)
          end

          # Calculate literal state index
          # XZ Utils literal_subcoder formula (from lzma_common.h:141-143):
          #   ((probs) + 3 * (((((pos) << 8) + (prev_byte)) & (literal_mask)) << (lc)))
          # where literal_mask = (1 << (lc + lp)) - 1
          #
          # The key insight is that (pos << 8) + prev_byte is computed FIRST,
          # then masked, THEN shifted by lc. This is different from our old formula
          # which added pos_part and prev_part separately.
          #
          # IMPORTANT: The literal_subcoder macro returns:
          #   probs + 3 * context_value_shifted
          # where context_value_shifted = context_value << lc
          #
          # For our implementation, we return context_value (unshifted) so that
          # the literal encoder can calculate the correct offset: 3 * context_value
          #
          # This creates (1 << (lc + lp)) unique contexts
          #
          # @return [Integer] Literal context value (unshifted, 0-7 for lc=3)
          def calculate_literal_state
            prev_byte = @dict.bytesize.positive? ? @dict[-1].ord : 0

            # XZ Utils formula from lzma_common.h:literal_mask_calc
            # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
            # For lc=3, lp=0: (256 << 0) - (256 >> 3) = 256 - 32 = 224 (0xE0)
            # IMPORTANT: Use the SAME formula as the decoder to ensure compatibility
            literal_mask = (0x100 << @lp) - (0x100 >> @lc)

            # Combine pos and prev_byte, then apply mask
            # IMPORTANT: (pos << 8) + prev_byte is computed FIRST, then masked
            (((@pos << 8) + prev_byte) & literal_mask)
          end

          # Write LZMA header
          #
          # SDK header format:
          # - Property byte: (lc + lp*9 + pb*45)
          # - Dictionary size: 4 bytes little-endian
          # - Uncompressed size: 8 bytes (0xFF for unknown size)
          #
          # @param uncompressed_size [Integer] Original data size
          # @return [void]
          def write_header(_uncompressed_size)
            # Property byte: (lc + lp*9 + pb*45)
            props = @lc + (@lp * 9) + (@pb * 45)
            @output.putc(props)

            # Dictionary size (4 bytes, little-endian)
            4.times do |i|
              @output.putc((@dict_size >> (i * 8)) & 0xFF)
            end

            # Uncompressed size (8 bytes, little-endian)
            # For SDK mode, use unknown size marker (0xFFFFFFFFFFFFFFFF)
            # This matches xz/lzma behavior for standalone streams
            8.times { @output.putc(0xFF) }
          end
        end
      end
    end
  end
end
