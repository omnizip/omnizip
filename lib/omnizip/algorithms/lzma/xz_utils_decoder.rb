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
require_relative "../../implementations/seven_zip/lzma/state_machine"
require_relative "literal_decoder"
require_relative "length_coder"
require_relative "distance_coder"
require_relative "range_decoder"
require_relative "bit_model"

module Omnizip
  module Algorithms
    # LZMA XZ Utils implementation
    #
    # This namespace contains the XZ Utils implementation of LZMA decoder.
    # XZ Utils is based on LZMA SDK but has been MODIFIED SIGNIFICANTLY.
    # This implementation is for XZ format (.xz files) ONLY.
    #
    # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c
    #
    # XZ Utils LZMA decoder
    #
    # This class implements XZ Utils' LZMA decoder (NOT LZMA SDK/7-Zip!)
    # XZ Utils is based on LZMA SDK but has been MODIFIED SIGNIFICANTLY.
    # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c
    #
    # This decoder is used for:
    # - XZ format (.xz files)
    # - LZMA2 compression in XZ format
    #
    module XzUtilsDecoderDebug
      # Debug helper to conditionally output debug messages
      # Set ENV['LZMA_DEBUG'] = 'true' to enable all debug output
      def self.debug_puts(*args)
        puts(*args) if ENV["LZMA_DEBUG"]
      end
    end

    # XZ Utils implementation of LZMA decoder
    #
    # IMPORTANT: This is NOT the LZMA SDK/7-Zip decoder!
    # XZ Utils modified LZMA significantly - this is XZ format only.
    # Components integrated:
    # - LiteralDecoder: Matched/unmatched literal decoding
    # - StateMachine: 12-state FSM for probability model selection
    # - LengthCoder: 3-level length decoding (low/mid/high)
    # - DistanceCoder: 64-slot distance decoding with aligned bits
    #
    # The decoder follows XZ Utils' exact decoding sequence:
    # 1. Read LZMA header (property byte, dict size, uncompressed size)
    # 2. Initialize range decoder and probability models
    # 3. Decode loop:
    #    - Decode is_match bit
    #    - If literal: decode byte (matched/unmatched)
    #    - If match: decode length and distance
    #    - Update state machine
    #    - Write to output
    # 4. Handle EOS marker
    #
    # @example Basic usage
    #   decoder = Omnizip::Algorithms::XzUtilsDecoder.new(input)
    #   data = decoder.decode_stream
    #
    # @example With output stream
    #   decoder = Omnizip::Algorithms::XzUtilsDecoder.new(input)
    #   File.open('output.txt', 'wb') { |f| decoder.decode_stream(f) }
    class XzUtilsDecoder
      include LZMA::Constants

      # Alias for nested classes for easier access
      BitModel = LZMA::BitModel
      LengthCoder = LZMA::LengthCoder
      DistanceCoder = LZMA::DistanceCoder
      LiteralDecoder = LZMA::LiteralDecoder
      RangeDecoder = LZMA::RangeDecoder
      SdkStateMachine = Implementations::SevenZip::LZMA::StateMachine

      attr_reader :lc, :lp, :pb, :dict_size, :uncompressed_size

      # XZ Utils dictionary constants (from lz_decoder.h)
      # See: /Users/mulgogi/src/external/xz/src/liblzma/lz/lz_decoder.h
      LZ_DICT_REPEAT_MAX = 288
      LZ_DICT_INIT_POS = 2 * LZ_DICT_REPEAT_MAX # = 576

      # Initialize the SDK-compatible decoder
      #
      # @param input [IO] Input stream of compressed data
      # @param options [Hash] Decoding options
      # @option options [Boolean] :lzma2_mode If true, initialize without reading header
      #                                      (for LZMA2 use, requires lc, lp, pb, dict_size, uncompressed_size)
      # @option options [Integer] :lc Literal context bits (required for lzma2_mode)
      # @option options [Integer] :lp Literal position bits (required for lzma2_mode)
      # @option options [Integer] :pb Position bits (required for lzma2_mode)
      # @option options [Integer] :dict_size Dictionary size (required for lzma2_mode)
      # @option options [Integer] :uncompressed_size Uncompressed size (required for lzma2_mode)
      # @option options [String] :preloaded_data Data to preload into dictionary (for LZMA2
      #                                         uncompressed chunks followed by compressed chunks)
      # @option options [Boolean] :validate_size If true, validate decoded size matches uncompressed_size
      #                                         (default: false, only for .lzma format)
      def initialize(input, options = {})
        @input = input
        @decoder_id = object_id # Track decoder instance ID
        puts "DEBUG LZMA::Decoder.new created[#{@decoder_id}]" if ENV["LZMA_DEBUG_DECODE_STREAM"]
        if ENV["LZMA_DEBUG_DECODE_STREAM"]
          warn "SDK Decoder #{@decoder_id} created"
        end
        @input = input

        # Check for preloaded data (from LZMA2 uncompressed chunks)
        @preloaded_data = options[:preloaded_data]
        @validate_size = options.fetch(:validate_size, false)
        @allow_eopm = options.fetch(:allow_eopm, nil)

        if options[:lzma2_mode]
          # Direct initialization for LZMA2 use (XZ Utils pattern)
          # The LZMA2 decoder provides parameters directly, no header to read
          # See: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:140-141
          @lc = options.fetch(:lc)
          @lp = options.fetch(:lp)
          @pb = options.fetch(:pb)
          @dict_size = options.fetch(:dict_size)
          @uncompressed_size = options.fetch(:uncompressed_size)
        else
          # Standalone LZMA file - read header from input
          read_header
        end
        validate_parameters
        init_models
        init_coders
      end

      # Decode a compressed stream
      #
      # Main decoding loop following SDK's LzmaDec_DecodeToDic logic:
      # 1. Initialize range decoder
      # 2. Process each position: decode literals/matches
      # 3. Detect EOS marker
      # 4. Return decompressed data
      #
      # XZ Utils dictionary system (from lz_decoder.h):
      # - pos starts at LZ_DICT_INIT_POS (576)
      # - full = pos - LZ_DICT_INIT_POS (count of valid bytes)
      # - has_wrapped = false until dictionary buffer wraps
      # - Distance validation: full > distance
      #
      # @param output [IO, nil] Optional output stream (if nil, returns String)
      # @param preserve_dict [Boolean] Whether to preserve dictionary from previous decode
      # @param check_rc_finished [Boolean] Whether to check if range decoder is finished
      # @return [String, Integer] Decompressed data or bytes written
      def decode_stream(output = nil, preserve_dict: false,
check_rc_finished: true)
        @decode_stream_call_count ||= 0
        @decode_stream_call_count += 1
        call_num = @decode_stream_call_count

        puts "DEBUG decode_stream START (call ##{call_num}): @pos=#{@pos.inspect}, @dict_full=#{@dict_full.inspect}, preserve_dict=#{preserve_dict}, @uncompressed_size=#{@uncompressed_size.inspect}" if ENV.fetch(
          "LZMA_DEBUG", nil
        ) && @dict_full && @dict_full >= 200 && @dict_full <= 230
        if ENV["LZMA_DEBUG_DECODE_STREAM"]
          warn "DEBUG decode_stream[#{@decoder_id}] START: preserve_dict=#{preserve_dict}, @pos=#{@pos.inspect}, @dict_full=#{@dict_full.inspect}, @dict_buf.object_id=#{@dict_buf&.object_id || 'nil'}, @dict_buf.size=#{@dict_buf&.size || 'nil'}"
        end

        # Initialize range decoder
        # For LZMA2, reuse persistent range decoder across chunks (like XZ Utils)
        # The range decoder is created in set_input when the first chunk is processed
        # See: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:140-141
        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_stream - reusing range decoder @input.pos=#{begin
            @input.pos
          rescue StandardError
            'N/A'
          end}, @range_decoder.class=#{@range_decoder.class}"
        end

        # Create range decoder if it doesn't exist (first chunk)
        # This happens when the decoder is created directly for LZMA (not LZMA2)
        unless @range_decoder
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: decode_stream - creating NEW range decoder"
          end
          @range_decoder = RangeDecoder.new(@input)
        end

        # Special case: empty input (uncompressed_size == 0)
        # Return immediately without trying to decode anything
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF && @uncompressed_size.zero?
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: decode_stream - empty input (uncompressed_size=0), returning immediately"
          end
          return "" # Empty output
        end

        # TEMP DEBUG: Trace first 10 iterations
        @debug_iter = 0

        # Track bytes decoded in this chunk (for multi-chunk streams)
        # This is needed to limit match lengths correctly when @uncompressed_size
        # represents only the current chunk's size, not the total size
        @chunk_bytes_decoded = 0

        # DEBUG: Show chunk_bytes_decoded initialization
        if @dict_full && @dict_full >= 220 && @dict_full <= 240 && ENV.fetch(
          "LZMA_DEBUG", nil
        )
          puts "DEBUG: chunk_bytes_decoded reset to 0 for chunk (call_num=#{call_num}, dict_full=#{@dict_full})"
        end

        # Initialize state and dictionary (XZ Utils system from lz_decoder.c)
        # See: /Users/mulgogi/src/external/xz/src/liblzma/lz/lz_decoder.c:56
        # For LZMA2 multi-chunk streams, state machine persists across chunks
        # Only reset when not preserving dictionary (first chunk)
        #
        # IMPORTANT: Initialize @state if it's nil (first call) OR if not preserving dict
        if @state.nil? || !preserve_dict
          @state = SdkStateMachine.new
        end

        # For LZMA2 multi-chunk streams, preserve dictionary across chunks
        # when preserve_dict is true (control >= 0x80 but < 0xA0)
        # For subsequent chunks, the reset() method handles dictionary reset
        # For the first chunk (when @dict_buf is nil), we need to init it here
        puts "DEBUG: Checking @dict_buf.nil? = #{@dict_buf.nil?}, preserve_dict=#{preserve_dict}" if ENV["LZMA_DEBUG_RESET"]
        if @dict_buf.nil?
          buf_size = @dict_size + LZ_DICT_INIT_POS
          @dict_buf = Array.new(buf_size, 0)
          @pos = LZ_DICT_INIT_POS
          @dict_full = 0
          @has_wrapped = false

          # Add preloaded data to dictionary (from LZMA2 uncompressed chunks)
          # This must be done before decoding so matches can reference this data
          if @preloaded_data && !@preloaded_data.empty?
            if ENV["LZMA_DEBUG_RESET"]
              warn "DEBUG: Preloading #{@preloaded_data.bytesize} bytes into dictionary[#{@decoder_id}]"
            end
            @preloaded_data.each_byte do |byte|
              @dict_buf[@pos] = byte
              @pos += 1
            end
            # Update dict_full to reflect preloaded data
            @dict_full = @pos - LZ_DICT_INIT_POS
            if ENV["LZMA_DEBUG_RESET"]
              warn "DEBUG: After preload - @pos=#{@pos}, @dict_full=#{@dict_full}"
              warn "  Preloaded data (hex): #{@preloaded_data[0..50].unpack1('H*')}"
            end
            @preloaded_data = nil # Clear after loading
          end

          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG: Dictionary init in decode_stream[#{@decoder_id}] - @pos=#{@pos}, @dict_full=#{@dict_full}, @dict_buf.size=#{@dict_buf.size}, @dict_buf.object_id=#{@dict_buf.object_id}"
            # Verify buffer initialization by checking a few positions
            warn "  Sample values: [576]=#{@dict_buf[576]}, [577]=#{@dict_buf[577]}, [578]=#{@dict_buf[578]}, [583]=#{@dict_buf[583]}"
          end
        end

        # Track starting position for multi-chunk streams
        # IMPORTANT: Calculate start_pos AFTER dictionary initialization!
        # This ensures that preloaded data (from LZMA2 uncompressed chunks) is
        # properly reflected in start_pos, so we only return NEW bytes.
        # For LZMA2, we need to return only the NEW bytes, not all bytes from LZ_DICT_INIT_POS
        start_pos = @pos || LZ_DICT_INIT_POS
        puts "DEBUG: start_pos=#{start_pos}, @pos=#{@pos.inspect}, @dict_full=#{@dict_full.inspect}, preserve_dict=#{preserve_dict}, @decoder_id=#{@decoder_id}" if ENV.fetch(
          "LZMA_DEBUG", nil
        ) && @dict_full && @dict_full >= 200 && @dict_full <= 230
        # Also show for chunk #1 start (dict_full around 227)
        puts "DEBUG: start_pos=#{start_pos}, @pos=#{@pos.inspect}, @dict_full=#{@dict_full.inspect}, @uncompressed_size=#{@uncompressed_size}, @decoder_id=#{@decoder_id}" if ENV.fetch(
          "LZMA_DEBUG", nil
        ) && @dict_full && @dict_full >= 225 && @dict_full <= 230

        # Initialize rep distances (XZ Utils initializes to 0)
        # See: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:1054-1055
        # For LZMA2 multi-chunk streams, rep distances persist across chunks
        # Only reset when not preserving dictionary (first chunk)
        #
        # IMPORTANT: Initialize rep distances if they're nil OR not preserving dict
        if @rep0.nil? || @rep1.nil? || @rep2.nil? || @rep3.nil? || !preserve_dict
          puts "DEBUG: Resetting rep distances to 0 (rep0.nil?=#{@rep0.nil?}, preserve_dict=#{preserve_dict})" if ENV.fetch(
            "LZMA_DEBUG", nil
          ) && @dict_full && @dict_full >= 200 && @dict_full <= 230
          @rep0 = 0
          @rep1 = 0
          @rep2 = 0
          @rep3 = 0
        end

        # Main decoding loop
        # XZ Utils pattern (lzma_decoder.c:305-306):
        # Set dict.limit = dict.pos + (size_t)(coder->uncompressed_size)
        # Then check dict.pos < dict.limit
        # Since our @pos starts at LZ_DICT_INIT_POS, we set limit accordingly
        # IMPORTANT: For multi-chunk streams, calculate limit from start_pos, not LZ_DICT_INIT_POS!
        # XZ Utils uses dict->pos (current position) + uncompressed_size
        # We use start_pos (current position) + @uncompressed_size
        limit = if @uncompressed_size == 0xFFFFFFFFFFFFFFFF
                  nil # No limit for unknown size
                else
                  start_pos + @uncompressed_size
                end

        # DEBUG: Show limit calculation for chunk #1
        if ENV.fetch("LZMA_DEBUG_LIMIT",
                     nil) && @dict_full && @dict_full >= 220 && @dict_full <= 240
          puts "DEBUG LIMIT CALCULATION: start_pos=#{start_pos}, @uncompressed_size=#{@uncompressed_size}, limit=#{limit.inspect}"
        end
        # DEBUG: Also show for dict_full around 293 (where the error occurs)
        if ENV.fetch("LZMA_DEBUG_LIMIT",
                     nil) && @dict_full && @dict_full >= 290 && @dict_full <= 300
          puts "DEBUG LIMIT CALCULATION at dict_full=#{@dict_full}: start_pos=#{start_pos}, @uncompressed_size=#{@uncompressed_size}, limit=#{limit.inspect}, @decoder_id=#{@decoder_id}"
        end

        iteration = 0
        loop do
          iteration += 1
          # DEBUG: Show every iteration after position 200
          if ENV.fetch("LZMA_DEBUG_ITER",
                       nil) && @dict_full && @dict_full >= 200 && @dict_full <= 500
            puts "DEBUG ITERATION ##{iteration}: pos=#{@pos}, dict_full=#{@dict_full}, limit=#{limit.inspect}"
          end
          # Check if we've reached the expected size (if known)
          # XZ Utils: checks dict.pos < dict.limit
          if ENV["LZMA_DEBUG_LIMIT"]
            compare_result = begin
              limit && @pos >= limit
            rescue StandardError
              "ERROR"
            end
            XzUtilsDecoderDebug.debug_puts "DEBUG LIMIT: iter=#{iteration}, pos=#{@pos.inspect}, dict_full=#{@dict_full}, limit=#{limit.inspect}, pos >= limit: #{compare_result}"
          end

          # Handle nil @pos or limit gracefully
          if limit && (@pos.nil? || limit.nil?)
            raise "Invalid state: @pos=#{@pos.inspect}, limit=#{limit.inspect}"
          end

          if ENV["LZMA_DEBUG_LIMIT"]
            XzUtilsDecoderDebug.debug_puts "DEBUG LIMIT: iter=#{iteration}, pos=#{@pos}, dict_full=#{@dict_full}, limit=#{limit}"
          end

          # DEBUG: Track position before decoding
          @pos if ENV["LZMA_DEBUG_POS"]

          # Decode is_match bit
          pos_state = @pos & ((1 << @pb) - 1)
          # XZ Utils: is_match[state][pos_state] where the array is NUM_STATES * (1 << pb)
          # The array stride changes with pb value
          model_index = (@state.value * (1 << @pb)) + pos_state

          # DEBUG: Show state before decode (for position tracking)
          if ENV["LZMA_DEBUG_POS_227"]
            XzUtilsDecoderDebug.debug_puts "DEBUG: Before is_match at pos=#{@pos}, dict_full=#{@dict_full}, state=#{@state.value}, pos_state=#{pos_state}"
          end

          # Debug trace (disabled - remove or enable with ENV var as needed)
          @debug_iter += 1

          # DEBUG: Trace is_match decision around position 256
          # IMPORTANT: Capture range/code BEFORE calling decode_bit
          if @dict_full.between?(255, 257)
            range = @range_decoder.instance_variable_get(:@range)
            code = @range_decoder.instance_variable_get(:@code)
            model = @is_match_models[model_index]
            XzUtilsDecoderDebug.debug_puts "  [IS_MATCH] pos=#{@pos}, dict_full=#{@dict_full}, state=#{@state.value}, pos_state=#{pos_state}, model_index=#{model_index}"
            XzUtilsDecoderDebug.debug_puts "    BEFORE decode: range=0x#{range.to_s(16)}, code=0x#{code.to_s(16)}, prob=#{model.probability}"
            # Enable detailed tracing for the critical is_match[0][0] decision
            $trace_is_match_0_0 = (@dict_full == 256)
          end

          if ENV.fetch("LZMA_DEBUG_ITER", nil)
            range = @range_decoder.instance_variable_get(:@range)
            code = @range_decoder.instance_variable_get(:@code)
            model = @is_match_models[model_index]
            bound = (range >> 11) * model.probability
            XzUtilsDecoderDebug.debug_puts ""
            XzUtilsDecoderDebug.debug_puts "ITER #{@debug_iter}:"
            XzUtilsDecoderDebug.debug_puts "  pos=#{@pos}, state=#{@state.value}, pos_state=#{pos_state}, model_index=#{model_index}"
            XzUtilsDecoderDebug.debug_puts "  dict_full=#{@dict_full}"
            XzUtilsDecoderDebug.debug_puts "  range=0x#{range.to_s(16)}, code=0x#{code.to_s(16)}, model.prob=#{model.probability}"
            XzUtilsDecoderDebug.debug_puts "  bound=0x#{bound.to_s(16)}, code < bound: #{code < bound}"
          end

          is_match = @range_decoder.decode_bit(@is_match_models[model_index])

          # DEBUG: Trace is_match and literal/match decisions around dict_full = 50-62
          if @dict_full.between?(50, 62)
            range_val = @range_decoder.instance_variable_get(:@range)
            code_val = @range_decoder.instance_variable_get(:@code)
            prob_val = @is_match_models[model_index].probability
            XzUtilsDecoderDebug.debug_puts "\n=== dict_full=#{@dict_full}: is_match=#{is_match}, state=#{@state.value}, pos_state=#{pos_state} ==="
            XzUtilsDecoderDebug.debug_puts "  model_index=#{model_index}, prob=#{prob_val}"
            XzUtilsDecoderDebug.debug_puts "  range=0x#{range_val.to_s(16).upcase}, code=0x#{code_val.to_s(16).upcase}"
          end

          if ENV.fetch("LZMA_DEBUG_ITER", nil)
            XzUtilsDecoderDebug.debug_puts "  is_match=#{is_match}"
          end

          # DEBUG: Show is_match result after decode
          if @dict_full.between?(255, 257)
            XzUtilsDecoderDebug.debug_puts "    AFTER decode: is_match=#{is_match}"
            XzUtilsDecoderDebug.debug_puts "    (is_match=0 means literal, is_match=1 means match)"
          end

          # DEBUG: Track what's happening around dict_full=227 (corruption point)
          if ENV["LZMA_DEBUG"] && @dict_full == 227
            puts "DEBUG CORRUPTION POINT: dict_full=#{@dict_full}, pos=#{@pos}"
            puts "  is_match=#{is_match}, state=#{@state.value}"
            range_val = @range_decoder.instance_variable_get(:@range)
            code_val = @range_decoder.instance_variable_get(:@code)
            puts "  range=0x#{range_val.to_s(16)}, code=0x#{code_val.to_s(16)}"
            puts "  dict_buf[#{@pos - 5}...#{@pos + 5}] = #{@dict_buf[[
              @pos - 5, LZ_DICT_INIT_POS
            ].max...[@pos + 5, @dict_buf.size - 1].min].inspect}"
          end

          if ENV["LZMA_DEBUG"] && @dict_full.between?(224, 235)
            puts "DEBUG pos #{@dict_full}: is_match=#{is_match}, state=#{@state.value}"
            if is_match.zero?
              puts "  Next byte should be literal"
            else
              puts "  Next byte should be match"
            end
          end

          # DEBUG: Verify first 256 bytes are correct
          if @dict_full == 256
            XzUtilsDecoderDebug.debug_puts ""
            XzUtilsDecoderDebug.debug_puts "  Verifying first 256 bytes:"
            # Check specific bytes around position 253
            XzUtilsDecoderDebug.debug_puts "  Byte 253: @dict_buf[#{LZ_DICT_INIT_POS + 253}]=#{@dict_buf[LZ_DICT_INIT_POS + 253].inspect} (expected 'i'=0x69)"
            XzUtilsDecoderDebug.debug_puts "  Byte 254: @dict_buf[#{LZ_DICT_INIT_POS + 254}]=#{@dict_buf[LZ_DICT_INIT_POS + 254].inspect} (expected 'n'=0x6E)"
            XzUtilsDecoderDebug.debug_puts "  Byte 255: @dict_buf[#{LZ_DICT_INIT_POS + 255}]=#{@dict_buf[LZ_DICT_INIT_POS + 255].inspect} (expected ' '=0x20)"
            all_correct = true
            256.times do |i|
              expected = i
              actual = @dict_buf[LZ_DICT_INIT_POS + i]
              if actual != expected
                all_correct = false
                if (i >= 253) && ENV.fetch("LZMA_DEBUG", nil)
                  puts "    Byte #{i}: expected 0x#{expected.to_s(16)}, got 0x#{actual.to_s(16)} MISMATCH!"
                end
              end
            end
            XzUtilsDecoderDebug.debug_puts "    First 256 bytes: #{all_correct ? 'ALL CORRECT ✓' : 'HAS MISMATCH'}"
            XzUtilsDecoderDebug.debug_puts ""
          end

          if ENV.fetch("LZMA_DEBUG", nil) && @pos >= 605 && @pos <= 615
            warn "DEBUG: is_match at pos=#{@pos}, state=#{@state.value}, pos_state=#{pos_state}, model_index=#{model_index}, is_match=#{is_match}"
          end

          if is_match.zero?
            # Decode literal
            decode_literal

            # Trace positions 45-65 for debugging good-1-lzma2-3.xz divergence
            if ENV.fetch("LZMA_DEBUG",
                         nil) && @dict_full >= 45 && @dict_full <= 65
              last_byte = @dict_buf[@pos - 1]
              range_after = @range_decoder.instance_variable_get(:@range)
              code_after = @range_decoder.instance_variable_get(:@code)
              puts "  literal decoded: 0x#{last_byte.to_s(16).upcase} ('#{last_byte.chr}') at pos=#{@pos - 1}, dict_full=#{@dict_full}"
              puts "    AFTER: range=0x#{range_after.to_s(16).upcase}, code=0x#{code_after.to_s(16).upcase}"
            end

            if ENV.fetch("LZMA_DEBUG_ITER", nil)
              last_byte = @dict_buf[@pos - 1]
              puts "  literal byte=0x#{last_byte.to_s(16)} ('#{last_byte.chr}')"
            end
            if ENV["LZMA_DEBUG_POS"] && @pos >= limit
              puts "DEBUG: Literal overshoot: pos=#{@pos}, limit=#{limit}, delta=#{@pos - limit}"
            end
          elsif decode_match
            # Decode match - returns true if EOS detected
            break
          end

          # XZ Utils: Check if we've reached the limit (known uncompressed size)
          # Reference: lzma_decoder.c:347, 680-692
          # When dict.pos == dict.limit, the decoder should stop
          # IMPORTANT: Must verify range decoder is finished (code == 0)
          # If code != 0, there's leftover data in the compressed stream (corruption)
          if limit && @pos >= limit
            puts "DEBUG LIMIT TRIGGERED (call #{call_num}): pos=#{@pos}, limit=#{limit}, dict_full=#{@dict_full}, chunk_bytes_decoded=#{@chunk_bytes_decoded}" if ENV["LZMA_DEBUG_LIMIT"]

            # XZ Utils pattern (lzma_decoder.c:689-700):
            # Check if range decoder is finished (code == 0)
            # - If finished → STREAM_END (success)
            # - If NOT finished AND allow_eopm is false → DATA_ERROR (corruption)
            # - If NOT finished AND allow_eopm is true → continue (expect EOPM)
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:689-700
            #
            # For LZMA2: @allow_eopm is false, so range decoder MUST be finished
            # For .lzma format: @allow_eopm may be true, so we continue decoding to find EOPM
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_decoder.h:138-139
            # rc_is_finished(range_decoder) = ((range_decoder).code == 0)
            #
            # NOTE: The check_rc_finished parameter is a legacy override for .lzma format
            # If explicitly set to false, it allows EOPM even when uncompressed size is known
            # Reference: alone_decoder.c:127 (LZMA_LZMA1EXT_ALLOW_EOPM)
            should_check = if @allow_eopm == true
                             # EOPM is explicitly allowed, skip the check
                             false
                           elsif @allow_eopm == false
                             # LZMA2 mode: always check (EOPM is not allowed)
                             true
                           else
                             # @allow_eopm is nil (not set, first chunk or legacy mode)
                             # Use check_rc_finished parameter as default
                             check_rc_finished
                           end

            if should_check
              # If EOPM is not allowed, range decoder MUST be finished
              unless @range_decoder.code.zero?
                raise Omnizip::DecompressionError,
                      "LZMA stream finished with leftover compressed data (range_decoder.code=#{@range_decoder.code}, expected 0). This indicates corruption in the compressed stream or an invalid EOPM for LZMA2."
              end
              break
            elsif @range_decoder.code.zero?
              # EOPM is allowed (e.g., LZMA_Alone format)
              # If range decoder is finished, we're done
              break
              # Otherwise, continue decoding to find EOPM marker
              # XZ Utils sets eopm_is_valid = true and continues
              # Reference: lzma_decoder.c:704
            end
          end

          # DEBUG: Show when approaching limit for chunk #1
          if ENV.fetch("LZMA_DEBUG_LIMIT",
                       nil) && limit && @pos >= limit - 10 && @pos < limit + 10
            puts "DEBUG NEAR LIMIT (call #{call_num}): pos=#{@pos}, limit=#{limit}, dict_full=#{@dict_full}, chunk_bytes_decoded=#{@chunk_bytes_decoded}, remaining=#{@uncompressed_size ? @uncompressed_size - @chunk_bytes_decoded : 'N/A'}"
          end

          # DEBUG: Show when we've passed the expected limit
          if ENV.fetch("LZMA_DEBUG_LIMIT",
                       nil) && limit && @pos >= limit && @pos < limit + 10
            puts "DEBUG PASSED LIMIT: pos=#{@pos}, limit=#{limit}, dict_full=#{@dict_full}, delta=#{@pos - limit}"
          end

          if ENV["LZMA_DEBUG_POS"] && @pos >= limit
            XzUtilsDecoderDebug.debug_puts "DEBUG: Overshoot detected: pos=#{@pos}, limit=#{limit}, delta=#{@pos - limit}"
          end
        end

        # Validate decoded size against expected uncompressed_size
        # Only for .lzma (LZMA_Alone) format where validate_size=true
        # For .lzma format with known uncompressed_size, verify we decoded the right amount
        # This catches "too_small_size-without-eopm" files where the header says 1 byte
        # but the compressed data produces more output
        # XZ format does NOT validate size at the LZMA decoder level - it's handled at block level
        if @validate_size && @uncompressed_size && @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          # Calculate actual decoded size (from start of data, not LZ_DICT_INIT_POS)
          actual_decoded_size = @pos - LZ_DICT_INIT_POS

          if actual_decoded_size != @uncompressed_size
            raise Omnizip::DecompressionError,
                  "LZMA stream size mismatch: expected #{@uncompressed_size} bytes, decoded #{actual_decoded_size} bytes. The file may be corrupted or have an invalid uncompressed size field."
          end

          # IMPORTANT: Check for leftover compressed data after EOPM
          # If EOPM was encountered (range_decoder.code == 0) but there's still data
          # in the input stream, the file is corrupted.
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/alone_decoder.c
          #
          # We only check for leftover data when:
          # 1. EOPM was encountered (code == 0) AND
          # 2. There's more data in the input stream
          #
          # If EOPM was NOT encountered (code != 0), leftover data is expected
          # (it's part of the compressed stream that we haven't read yet).
          if @allow_eopm && @range_decoder&.code&.zero? && @range_decoder.instance_variable_get(:@stream)
            stream = @range_decoder.instance_variable_get(:@stream)
            # Try to peek at the next byte - if available, there's data AFTER EOPM
            begin
              next_byte = stream.getbyte
              if next_byte
                # Put the byte back
                stream.ungetbyte(next_byte) if stream.respond_to?(:ungetbyte)
                raise Omnizip::DecompressionError,
                      "LZMA_Alone file has data after the end-of-payload marker. The file may be corrupted or contain concatenated streams."
              end
            rescue IOError, EOFError
              # Stream doesn't support peeking or is exhausted, that's fine
            end
          elsif !@allow_eopm && @range_decoder&.instance_variable_get(:@stream)
            # For LZMA2 mode (EOPM not allowed): check for leftover data
            stream = @range_decoder.instance_variable_get(:@stream)
            begin
              next_byte = stream.getbyte
              if next_byte
                stream.ungetbyte(next_byte) if stream.respond_to?(:ungetbyte)
                raise Omnizip::DecompressionError,
                      "LZMA_Alone file has more compressed data than expected. The uncompressed size field (#{@uncompressed_size} bytes) appears to be too small."
              end
            rescue IOError, EOFError
              # Stream doesn't support peeking or is exhausted, that's fine
            end
          end
        end

        # Return output - only the valid portion of dictionary
        # XZ Utils: valid data starts from LZ_DICT_INIT_POS onwards
        # IMPORTANT: For LZMA2 multi-chunk streams, only return NEW bytes since start_pos!
        # This ensures each chunk returns only its own output, not previous chunks' output.
        if ENV["DEBUG_DICT_BUF"]
          XzUtilsDecoderDebug.debug_puts "DEBUG: start_pos=#{start_pos}, @pos=#{@pos.inspect}, @dict_buf.size=#{@dict_buf.size}, LZ_DICT_INIT_POS=#{LZ_DICT_INIT_POS}"
        end
        valid_bytes = @dict_buf[start_pos...@pos]
        # DEBUG: Show return value calculation
        puts "DEBUG RETURN CALCULATION: call_num=#{call_num}, start_pos=#{start_pos}, @pos=#{@pos}, valid_bytes.size=#{@dict_buf[start_pos...@pos].size}, dict_full=#{@dict_full}, chunk_bytes_decoded=#{@chunk_bytes_decoded}" if ENV.fetch(
          "LZMA_DEBUG", nil
        ) && @dict_full && @dict_full >= 220 && @dict_full <= 240 && call_num == 2
        puts "DEBUG RETURN CALCULATION: call_num=#{call_num}, start_pos=#{start_pos}, @pos=#{@pos}, valid_bytes.size=#{@dict_buf[start_pos...@pos].size}, dict_full=#{@dict_full}, chunk_bytes_decoded=#{@chunk_bytes_decoded}" if ENV["LZMA_DEBUG"] && call_num == 2
        # Filter out nil values (can happen during dictionary reset transitions)
        valid_bytes = valid_bytes.map { |b| b.nil? ? 0 : b }
        if ENV["DEBUG_DICT_BUF"]
          XzUtilsDecoderDebug.debug_puts "DEBUG: valid_bytes=#{begin
            valid_bytes.size
          rescue StandardError
            valid_bytes.inspect
          end}"
        end
        valid_data = valid_bytes.pack("C*")
        if output
          output.write(valid_data.force_encoding(Encoding::BINARY))
          valid_data.bytesize
        else
          valid_data.force_encoding(Encoding::BINARY)
        end
      end

      # Reset the decoder state for reuse with new properties
      #
      # XZ Utils pattern (lzma_decoder.c:1034-1083):
      # - Resets state machine and rep distances
      # - Resets range decoder
      # - Reinitializes all probability models
      # - Preserves dictionary (managed externally by LZMA2 decoder)
      #
      # @param new_lc [Integer, nil] New lc value (if nil, keeps current)
      # @param new_lp [Integer, nil] New lp value (if nil, keeps current)
      # @param new_pb [Integer, nil] New pb value (if nil, keeps current)
      # @param preserve_dict [Boolean] If true, preserve dictionary state (pos, dict_full)
      # @return [void]
      def reset(new_lc: nil, new_lp: nil, new_pb: nil, preserve_dict: false)
        if ENV["LZMA_DEBUG_RESET"]
          warn "DEBUG reset[#{@decoder_id}] called: preserve_dict=#{preserve_dict}, @pos=#{@pos.inspect}, @dict_full=#{@dict_full.inspect}, @dict_buf.size=#{@dict_buf&.size || 'nil'}, nil_count=#{@dict_buf&.count(nil) || 'N/A'}"
        end

        # DEBUG: Trace reset calls around position 224-227
        if @dict_full && @dict_full >= 220 && @dict_full <= 230
          XzUtilsDecoderDebug.debug_puts "\n=== reset called at dict_full=#{@dict_full} ==="
          XzUtilsDecoderDebug.debug_puts "  preserve_dict=#{preserve_dict}"
          XzUtilsDecoderDebug.debug_puts "  Before reset: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # Update properties if provided
        properties_changed = !!(new_lc || new_lp || new_pb)
        @lc = new_lc if new_lc
        @lp = new_lp if new_lp
        @pb = new_pb if new_pb

        # Reset state machine (XZ Utils line 1053)
        # Always create a new state machine when resetting
        @state = SdkStateMachine.new

        # Reset rep distances (XZ Utils lines 1071-1074)
        # IMPORTANT: ALWAYS reset rep distances to 0 when state is reset
        # This happens for both control=0xE0 (dict reset) and control=0xC0 (state reset)
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:1071-1074
        @rep0 = 0
        @rep1 = 0
        @rep2 = 0
        @rep3 = 0

        # Reset range decoder for next chunk
        # XZ Utils pattern (lzma_decoder.c:1061):
        # - rc_reset sets range=UINT32_MAX, code=0, init_bytes_left=5
        # - This MUST happen during reset, not deferred to decode_stream
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:1061
        if @range_decoder
          @range_decoder.reset
          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG reset[#{@decoder_id}]: Reset range_decoder, code=0x#{@range_decoder.code.to_s(16)}, init_bytes_remaining=#{@range_decoder.instance_variable_get(:@init_bytes_remaining)}"
          end
        end

        # Reinitialize probability models (XZ Utils lines 1064-1082)
        # IMPORTANT: Use reset_models (reset in place) instead of init_models (create new)
        # for state reset only. Only create new models when properties change.
        if properties_changed
          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG reset[#{@decoder_id}]: Properties changed, calling init_models (create new arrays)"
          end
          init_models
        else
          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG reset[#{@decoder_id}]: No properties changed, calling reset_models (reset in place)"
          end
          reset_models
        end

        # Reinitialize coders (needed for pb changes)
        # Only recreate coders when properties have changed
        if properties_changed
          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG reset[#{@decoder_id}]: Properties changed, calling init_coders (create new coders)"
          end
          init_coders
        elsif ENV["LZMA_DEBUG_RESET"]
          warn "DEBUG reset[#{@decoder_id}]: No properties changed, skipping init_coders (preserve existing coders)"
        end

        # Reset dictionary position and full count (XZ Utils pattern)
        # Only reset if preserve_dict is false
        unless preserve_dict
          # Reinitialize dictionary buffer
          # XZ Utils allocates a new buffer for each dictionary reset
          @dict_buf = Array.new(@dict_size + LZ_DICT_INIT_POS, 0)
          @pos = LZ_DICT_INIT_POS
          @dict_full = 0
          @has_wrapped = false
          if ENV["LZMA_DEBUG_RESET"]
            warn "DEBUG reset after dict reset[#{@decoder_id}]: @pos=#{@pos}, @dict_full=#{@dict_full}, @dict_buf.size=#{@dict_buf.size}, @dict_buf.object_id=#{@dict_buf.object_id}, nil_count=#{@dict_buf.count(nil)}"
            # Verify buffer initialization by checking a few positions
            warn "  Sample values: [576]=#{@dict_buf[576]}, [577]=#{@dict_buf[577]}, [578]=#{@dict_buf[578]}, [583]=#{@dict_buf[583]}"
          end
        end

        nil
      end

      # Reset all probability models in place (without creating new arrays)
      #
      # This matches XZ Utils init_temporals behavior for control >= 0xA0.
      # Unlike init_models which creates new arrays, this resets existing
      # BitModels in place to preserve object identity for any references.
      #
      # @return [void]
      def reset_models
        # Reset literal models
        @literal_models.each(&:reset)

        # Reset match/rep models
        @is_match_models.each(&:reset)
        @is_rep_models.each(&:reset)
        @is_rep0_models.each(&:reset)
        @is_rep1_models.each(&:reset)
        @is_rep2_models.each(&:reset)
        @is_rep0_long_models.each(&:reset)

        # Reset length coders
        @length_coder.reset_models
        @rep_length_coder.reset_models

        # Reset distance coder
        @distance_coder.reset_models
      end

      # Reset only state machine and rep distances, preserve probability models
      #
      # XZ Utils pattern for state reset only (control >= 0xA0):
      # - Reset state machine
      # - Reset rep distances
      # - Reset probability models (via reset_models)
      # - Reset range decoder (rc_reset + rc_read_init)
      # - PRESERVE dictionary content (no dict_reset)
      #
      # XZ Utils source (lzma2_decoder.c):
      # - For control >= 0xA0: calls lzma_lzma_decoder_reset(decoder, NULL)
      # - lzma_lzma_decoder_reset always calls init_temporals which resets probability models
      #
      # @return [void]
      # Prepare state reset - called BEFORE setting new input
      #
      # Resets state machine, rep distances, and probability models.
      # The range decoder will be reset in finish_state_reset AFTER
      # the new input is set (to match XZ Utils lzma_decoder_reset behavior).
      #
      # For LZMA2 control >= 0xC0, this is called before set_input to reset
      # everything except the range decoder for the new chunk.
      #
      # @return [void]
      def prepare_state_reset
        # DEBUG: Trace when prepare_state_reset is called
        if ENV["LZMA_DEBUG"]
          XzUtilsDecoderDebug.debug_puts "\n=== prepare_state_reset called (decoder_id=#{@decoder_id}) ==="
          XzUtilsDecoderDebug.debug_puts "  Before reset: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # Reset state machine (XZ Utils line 1053)
        @state = SdkStateMachine.new

        # Reset rep distances (XZ Utils lines 1054-1057)
        @rep0 = 0
        @rep1 = 0
        @rep2 = 0
        @rep3 = 0

        # DEBUG: Show after reset
        if ENV["LZMA_DEBUG"]
          XzUtilsDecoderDebug.debug_puts "  After reset: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # Reset probability models (XZ Utils init_temporals for control >= 0xA0)
        reset_models

        if ENV["LZMA_DEBUG"]
          XzUtilsDecoderDebug.debug_puts "=== end prepare_state_reset (range decoder will be reset in finish_state_reset) ==="
        end

        nil
      end

      # Reset state machine only - preserves rep distances
      #
      # This is used for control >= 0xA0 but < 0xC0 where we want
      # to reset the state machine but preserve rep distances from
      # the previous chunk.
      #
      # @return [void]
      def reset_state_machine_only
        # DEBUG: Trace when reset_state_machine_only is called
        if @dict_full && @dict_full >= 220 && @dict_full <= 230
          XzUtilsDecoderDebug.debug_puts "\n=== reset_state_machine_only called at dict_full=#{@dict_full} (decoder_id=#{@decoder_id}) ==="
          XzUtilsDecoderDebug.debug_puts "  Before reset: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # Reset state machine only (XZ Utils line 1053)
        @state = SdkStateMachine.new

        # Reset probability models (XZ Utils init_temporals for control >= 0xA0)
        reset_models

        # DEBUG: Show after reset (note: rep distances are preserved)
        if @dict_full && @dict_full >= 220 && @dict_full <= 230
          XzUtilsDecoderDebug.debug_puts "  After reset: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3}) (preserved)"
        end

        nil
      end

      # Finish state reset - called AFTER setting new input
      #
      # Resets the range decoder to read from the new input stream.
      # This completes the state reset process started by prepare_state_reset.
      #
      # XZ Utils pattern (lzma_decoder.c:1034-1083):
      # - rc_reset is called as part of lzma_decoder_reset
      # - rc_reset sets range = UINT32_MAX, code = 0, init_bytes_left = 5
      # - The 5 initialization bytes are read during the first normalize calls
      #
      # @return [void]
      def finish_state_reset
        # Reset range decoder (XZ Utils rc_reset)
        # This reinitializes the range decoder for the new chunk
        # The reset will read 5 bytes from the input when decode_stream starts
        if @range_decoder
          if ENV["LZMA_DEBUG"]
            input_pos = begin
              @input.pos
            rescue StandardError
              "N/A"
            end
            input_size = begin
              @input.size
            rescue StandardError
              "N/A"
            end
            XzUtilsDecoderDebug.debug_puts "=== finish_state_reset: resetting range_decoder, input pos=#{input_pos}, size=#{input_size}"
          end
          @range_decoder.reset
          if ENV["LZMA_DEBUG"]
            input_pos_after = begin
              @input.pos
            rescue StandardError
              "N/A"
            end
            XzUtilsDecoderDebug.debug_puts "=== finish_state_reset: after reset, input pos=#{input_pos_after}, range_decoder.code=0x#{@range_decoder.code.to_s(16)}"
          end
        end
      end

      def reset_state_only
        # For backward compatibility, call both prepare and finish
        prepare_state_reset
        finish_state_reset
      end

      # Reset only the range decoder for next chunk
      #
      # XZ Utils pattern (lzma_decoder.c:1014-1017):
      # When LZMA chunk ends (LZMA_STREAM_END), reset range decoder
      # for next LZMA2 chunk, but preserve state and probability models.
      #
      # Note: This method is a no-op in our implementation because
      # decode_stream creates a fresh RangeDecoder for each chunk.
      # The range decoder initialization happens automatically when
      # the new RangeDecoder is created with the new input.
      #
      # @return [void]
      def reset_range_decoder
        # No-op: RangeDecoder is created fresh in decode_stream
      end

      # Set new input stream for chunked decoding
      #
      # For LZMA2, the range decoder is persistent across chunks and is
      # reset separately via prepare_state_reset + finish_state_reset.
      # This method just updates the input stream reference.
      #
      # @param new_input [IO] New input stream
      # @return [void]
      def set_input(new_input)
        @input = new_input

        # DEBUG: Trace input stream contents
        if ENV.fetch("LZMA_DEBUG",
                     nil) && @dict_full && @dict_full >= 220 && @dict_full <= 230
          puts "\n=== set_input at dict_full=#{@dict_full} ==="
          puts "  new_input.size=#{new_input.size}"
          puts "  new_input.pos=#{new_input.pos}"
          puts "  new_input.class=#{new_input.class}"

          # Read first 10 bytes manually
          first_bytes = []
          10.times do |_i|
            byte = new_input.getbyte
            break if byte.nil?

            first_bytes << byte
          end
          puts "  First 10 bytes: #{first_bytes.map do |b|
            "0x#{b.to_s(16).upcase}"
          end.join(' ')}"

          new_input.rewind
          test_byte = new_input.getbyte
          puts "  Test getbyte: 0x#{test_byte.to_s(16).upcase}" if test_byte
          new_input.rewind
        end

        # Create range decoder if it doesn't exist (first chunk)
        if @range_decoder.nil?
          @range_decoder = RangeDecoder.new(@input)
          if ENV["LZMA_DEBUG"]
            XzUtilsDecoderDebug.debug_puts "=== set_input: created NEW range_decoder, input has #{@input.size} bytes"
          end
        else
          # Update the range decoder's input stream to the new input
          # This is needed because RangeDecoder holds a reference to the stream
          @range_decoder.update_stream(@input)
          if ENV["LZMA_DEBUG"]
            XzUtilsDecoderDebug.debug_puts "=== set_input: reusing range_decoder, new input has #{@input.size} bytes, pos=#{@input.pos}"
          end
        end
      end

      # Add uncompressed data to the dictionary
      #
      # XZ Utils pattern (lzma2_decoder.c:195, dict_write):
      # - Copy uncompressed data to the dictionary as-is
      # - Update dict_full to reflect new data
      # - This allows subsequent compressed chunks to reference the data
      #
      # This is used by LZMA2 decoder for uncompressed chunks (control=0x1 or 0x2)
      #
      # @param data [String] Uncompressed data to add to dictionary
      # @return [void]
      def add_to_dictionary(data)
        if ENV["LZMA_DEBUG"]
          old_dict_full = @dict_full
          XzUtilsDecoderDebug.debug_puts "=== add_to_dictionary: adding #{data.bytesize} bytes to dictionary[#{@decoder_id}], current dict_full=#{@dict_full}, pos=#{@pos}"
        end

        data.each_byte do |byte|
          @dict_buf[@pos] = byte
          @pos += 1
        end

        # Update dict_full to reflect new data
        @dict_full = @pos - LZ_DICT_INIT_POS

        # Check if we've reached the maximum dictionary size
        if @dict_full >= @dict_size
          @dict_full = @dict_size
        end

        if ENV["LZMA_DEBUG"]
          XzUtilsDecoderDebug.debug_puts "=== add_to_dictionary: after adding, dict_full=#{@dict_full} (was #{old_dict_full}), pos=#{@pos}"
        end
      end

      # Set uncompressed size for chunked decoding
      #
      # XZ Utils pattern (lzma2_decoder.c:140-141):
      # Pass the chunk's uncompressed_size to the LZMA decoder
      # for each LZMA2 chunk.
      #
      # @param size [Integer] Uncompressed size for current chunk
      # @param allow_eopm [Boolean] Whether to allow end-of-payload marker
      # @return [void]
      def set_uncompressed_size(size, allow_eopm: true)
        @uncompressed_size = size
        @allow_eopm = allow_eopm
        # DEBUG: Track when uncompressed size is set
        if ENV["LZMA_DEBUG"]
          puts "DEBUG set_uncompressed_size: size=#{size}, @decoder_id=#{@decoder_id}, @dict_full=#{@dict_full}"
        end
      end

      private

      # Read and parse LZMA header
      #
      # SDK header format:
      # - Property byte: (lc + lp*9 + pb*45)
      # - Dictionary size: 4 bytes little-endian
      # - Uncompressed size: 8 bytes (0xFF for unknown size)
      #
      # @return [void]
      # @raise [RuntimeError] If header is invalid
      def read_header
        # Property byte
        props = @input.getbyte
        raise "Invalid LZMA header" if props.nil?

        @lc = props % 9
        remainder = props / 9
        @lp = remainder % 5
        @pb = remainder / 5

        # Dictionary size (4 bytes, little-endian)
        @dict_size = 0
        4.times do |i|
          byte = @input.getbyte
          raise "Incomplete header" if byte.nil?

          @dict_size |= (byte << (i * 8))
        end

        # Uncompressed size (8 bytes, little-endian)
        @uncompressed_size = 0
        8.times do |i|
          byte = @input.getbyte
          raise "Incomplete header" if byte.nil?

          @uncompressed_size |= (byte << (i * 8))
        end
      end

      # Validate parameters
      #
      # @return [void]
      # @raise [RuntimeError] If parameters are invalid
      def validate_parameters
        raise "Invalid lc (#{@lc})" unless @lc.between?(0, 8)
        raise "Invalid lp (#{@lp})" unless @lp.between?(0, 4)
        raise "Invalid pb (#{@pb})" unless @pb.between?(0, 4)
      end

      # Initialize probability models
      #
      # SDK allocates models following exact structure from LzmaDec.c:
      # - Literal models: (1 << (lc+lp)) contexts * 0x300 models each
      # - Match models: NUM_STATES * pos_states models (where pos_states = 1 << pb)
      # - Rep models: NUM_STATES models each
      #
      # Must match SdkEncoder's model structure exactly.
      # CRITICAL: When pb changes, models must be recreated with new pos_states!
      #
      # @return [void]
      def init_models
        # Calculate pos_states based on current @pb value
        pos_states = 1 << @pb
        @pos_states = pos_states # Store for use in indexing

        # Literal models: XZ Utils compact layout
        # context_value ranges from 0 to literal_mask (using XZ Utils formula)
        # base_offset = (context_value * 3) << lc
        # For unmatched mode: max index = (max_context_value * 3) << lc + 256
        # For matched mode: max index = (max_context_value * 3) << lc + offset + match_bit + symbol
        #   where offset, match_bit, and symbol can each be up to 0x100
        # So max matched index = base_offset + 0x100 + 0x100 + 0x100 = base_offset + 0x300
        # XZ Utils formula for literal_mask: (0x100 << lp) - (0x100 >> lc)
        literal_mask = (0x100 << @lp) - (0x100 >> @lc)
        max_context_value = literal_mask
        max_base_offset = (max_context_value * 3) << @lc
        max_model_index = max_base_offset + 0x300 # accommodate matched mode (offset + match_bit + symbol)
        @literal_models = Array.new(max_model_index + 1) do
          BitModel.new
        end

        # Match/rep decision models
        # IMPORTANT: Use current pos_states, not POS_STATES_MAX
        # This ensures models are correctly sized when pb changes
        @is_match_models = Array.new(NUM_STATES * pos_states) do
          BitModel.new
        end
        @is_rep_models = Array.new(NUM_STATES) { BitModel.new }
        @is_rep0_models = Array.new(NUM_STATES) { BitModel.new }
        @is_rep1_models = Array.new(NUM_STATES) { BitModel.new }
        @is_rep2_models = Array.new(NUM_STATES) { BitModel.new }
        @is_rep0_long_models = Array.new(NUM_STATES * pos_states) do
          BitModel.new
        end
      end

      # Initialize SDK coders
      #
      # @return [void]
      def init_coders
        @literal_decoder = LiteralDecoder.new
        pos_states = 1 << @pb
        @length_coder = LengthCoder.new(pos_states)
        @rep_length_coder = LengthCoder.new(pos_states)
        @distance_coder = DistanceCoder.new(NUM_LEN_TO_POS_STATES)

        if ENV["TRACE_MODEL_INIT"]
          puts "[XzUtilsDecoder.init] slot_encoders len_state=0 object_id=#{@distance_coder.instance_variable_get(:@slot_encoders)[0].object_id}"
          puts "[XzUtilsDecoder.init] slot_encoders[0][1] object_id=#{@distance_coder.instance_variable_get(:@slot_encoders)[0][1].object_id}"
          puts "[XzUtilsDecoder.init] is_match_models object_id=#{@is_match_models.object_id}"
          puts "[XzUtilsDecoder.init] is_match_models[0] object_id=#{@is_match_models[0].object_id}"
        end

        # Update probability model indices to match new pos_states
        # This is critical when pb changes between chunks
        @pos_states = pos_states
      end

      # Reset distance coder probability models
      #
      # Called during state reset (control >= 0xA0) to reset the distance
      # coder's probability models to initial values. This matches XZ Utils
      # behavior where init_temporals resets all probability models.
      #
      # @return [void]
      def reset_distance_coder
        @distance_coder.reset_models
      end

      # Decode a literal byte
      #
      # SDK decoding sequence (from LzmaDec.c):
      # 1. Calculate literal state
      # 2. Decode literal (matched or unmatched based on state)
      # 3. Update state machine
      # 4. Update dictionary and position
      #
      # XZ Utils dict_put pattern (from lz_decoder.h:270-276):
      # dict->buf[dict->pos++] = byte;
      # if (!dict->has_wrapped)
      #     dict->full = dict->pos - LZ_DICT_INIT_POS;
      #
      # @return [void]
      def decode_literal
        # DEBUG: Trace literals around position 224-227
        old_dict_full = @dict_full

        # DEBUG: Track how many times we're called for each position
        if ENV["LZMA_DEBUG_DECODE_LITERAL"]
          caller_info = caller(1..1).first
          XzUtilsDecoderDebug.debug_puts "DEBUG decode_literal[#{@decoder_id}]: pos=#{@pos}, dict_full=#{@dict_full}, from=#{caller_info.label}"
        end

        # DEBUG: Check array integrity before decode
        if ENV.fetch("LZMA_DEBUG_ARRAY",
                     nil) && @dict_full.positive? && @pos > 1
          idx = @pos - 1
          if @dict_buf[idx].nil?
            raise "DEBUG before decode: @dict_buf[#{idx}] is nil! @pos=#{@pos}, @dict_full=#{@dict_full}, @dict_buf.size=#{@dict_buf.size}, nil_count=#{@dict_buf.count(nil)}"
          end
        end

        # Calculate literal state using SDK formula
        lit_state = calculate_literal_state

        # DEBUG: Trace lit_state at position 61
        if @dict_full == 61 && ENV["TRACE_LITERAL_61"]
          XzUtilsDecoderDebug.debug_puts "=== CALC_LITERAL_STATE at dict_full=61 ==="
          XzUtilsDecoderDebug.debug_puts "  prev_byte=#{@dict_full.positive? ? @dict_buf[@pos - 1] : 0}"
          XzUtilsDecoderDebug.debug_puts "  lit_state=#{lit_state}"
          XzUtilsDecoderDebug.debug_puts "  lc=#{@lc}, lp=#{@lp}"
          XzUtilsDecoderDebug.debug_puts "  state.value=#{@state.value}"
          XzUtilsDecoderDebug.debug_puts "  use_matched_literal?=#{@state.use_matched_literal?}"
          XzUtilsDecoderDebug.debug_puts "  dict_full.positive?=#{@dict_full.positive?}"
          puts
        end

        # Decode literal (matched or unmatched)
        # Check if dictionary has any valid bytes (XZ Utils: dict->full > 0)
        if @state.use_matched_literal? && @dict_full.positive?
          # DEBUG: Track which branch is taken
          if @dict_full == 61 && ENV["TRACE_LITERAL_61"]
            XzUtilsDecoderDebug.debug_puts "  TAKING MATCHED LITERAL PATH"
            XzUtilsDecoderDebug.debug_puts "  rep0=#{@rep0}"
            match_byte_pos_calc = LZ_DICT_INIT_POS + @dict_full - @rep0 - 1
            XzUtilsDecoderDebug.debug_puts "  match_byte_pos (calc)=#{match_byte_pos_calc}"
            puts
          end

          # Matched literal: use match byte from dictionary at distance rep0
          # XZ Utils dict_get pattern: dict->buf[dict->pos - distance - 1]
          # IMPORTANT: dict->pos in XZ Utils is the actual output position (dict->full),
          # not the buffer position with offset!
          # omnizip uses @pos for buffer position (includes LZ_DICT_INIT_POS offset)
          # and @dict_full for actual output position (starts at 0)
          # So we must convert: buffer_pos = LZ_DICT_INIT_POS + (output_pos - rep0 - 1)
          match_byte_pos = LZ_DICT_INIT_POS + @dict_full - @rep0 - 1
          match_byte = @dict_buf[match_byte_pos]
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: matched literal - dict_full=#{@dict_full}, rep0=#{@rep0}, reading dict_buf[#{match_byte_pos}]=0x#{match_byte.to_s(16).upcase} ('#{match_byte.chr}'), lit_state=#{lit_state}, state=#{@state.value}"
          end
          byte = @literal_decoder.decode_matched(match_byte, lit_state, @lc,
                                                 @range_decoder, @literal_models)

          # DEBUG: Trace decoded byte at position 61
          if @dict_full == 61 && ENV["TRACE_LITERAL_61"]
            XzUtilsDecoderDebug.debug_puts "  DECODED MATCHED LITERAL: 0x#{byte.to_s(16).upcase} ('#{byte.chr}')"
            XzUtilsDecoderDebug.debug_puts "  match_byte=0x#{match_byte.to_s(16).upcase} ('#{match_byte.chr}')"
            puts
          end
        else
          # Unmatched literal: simple 8-bit decoding
          if @dict_full == 61 && ENV["TRACE_LITERAL_61"]
            XzUtilsDecoderDebug.debug_puts "  TAKING UNMATCHED LITERAL PATH"
            puts
          end

          if ENV["LZMA_DEBUG"]
            warn "DEBUG: calling decode_unmatched - pos=#{@pos}, lit_state=#{lit_state}"
          end
          byte = @literal_decoder.decode_unmatched(lit_state, @lc,
                                                   @range_decoder, @literal_models)
        end

        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_literal RETURNED - pos=#{@pos}, byte=#{'0x%02X' % byte} ('#{byte.chr}'), lit_state=#{lit_state}"
        end

        # DEBUG: Check byte value at critical positions
        if @dict_full == 256
          XzUtilsDecoderDebug.debug_puts "DEBUG: About to store 257th byte (pos=#{@pos}, dict_full=#{@dict_full})"
          XzUtilsDecoderDebug.debug_puts "  byte.class=#{byte.class}"
          XzUtilsDecoderDebug.debug_puts "  byte=#{byte.inspect}"
          XzUtilsDecoderDebug.debug_puts "  byte.is_a?(Integer)=#{byte.is_a?(Integer)}"
          if byte.is_a?(Integer)
            XzUtilsDecoderDebug.debug_puts "  byte value=#{byte}"
            XzUtilsDecoderDebug.debug_puts "  Expected byte value=0"
          else
            XzUtilsDecoderDebug.debug_puts "  byte is not an Integer!"
            XzUtilsDecoderDebug.debug_puts "  byte.ord=#{byte.ord}"
          end
        end

        if ENV["LZMA_DEBUG"]
          decoded_bytes = @dict_full.positive? ? @dict_buf[LZ_DICT_INIT_POS..].map(&:chr).join : ""
          warn "DEBUG: decode_literal - pos=#{@pos}, byte=#{'0x%02X' % byte} ('#{byte.chr}'), state=#{@state.value}, dict_full=#{@dict_full}, decoded_so_far='#{decoded_bytes[-10..]}'"
        end

        # DEBUG: Detailed trace around position 256
        if ENV["LZMA_DEBUG"] && @dict_full.between?(230, 265)
          expected = @dict_full % 256
          match = byte == expected ? "✓" : "✗ MISMATCH!"
          XzUtilsDecoderDebug.debug_puts "  [LITERAL] dict_full=#{@dict_full}: 0x#{byte.to_s(16).upcase} (expected 0x#{expected.to_s(16).upcase}) #{match}"
          if @dict_full == 233
            XzUtilsDecoderDebug.debug_puts "  DETAILED TRACE at dict_full=233 (pos=#{@pos}):"
            XzUtilsDecoderDebug.debug_puts "    byte=0x#{byte.to_s(16)} ('#{begin
              byte.chr
            rescue StandardError
              '?'
            end}')"
            XzUtilsDecoderDebug.debug_puts "    state.value=#{@state.value}, lit_state=#{lit_state}"
            XzUtilsDecoderDebug.debug_puts "    use_matched_literal?=#{@state.use_matched_literal?}"
            prev_byte_val = @dict_full.positive? ? @dict_buf[@pos - 1] : "N/A"
            XzUtilsDecoderDebug.debug_puts "    prev_byte=#{prev_byte_val.inspect} (#{if prev_byte_val.is_a?(Integer)
                                                                                        "0x#{prev_byte_val.to_s(16)} ('#{begin
                                                                                          prev_byte_val.chr
                                                                                        rescue StandardError
                                                                                          '?'
                                                                                        end}')"
                                                                                      else
                                                                                        'N/A'
                                                                                      end})"
            XzUtilsDecoderDebug.debug_puts "    range_decoder.range=0x#{@range_decoder.range.to_s(16)}, range_decoder.code=0x#{@range_decoder.code.to_s(16)}"
            XzUtilsDecoderDebug.debug_puts "    input.pos=#{@input.pos}, input.size=#{@input.size}"
          end
          if @dict_full == 256
            XzUtilsDecoderDebug.debug_puts "    pos=#{@pos}, lit_state=#{lit_state}, state.value=#{@state.value}"
            XzUtilsDecoderDebug.debug_puts "    use_matched_literal?=#{@state.use_matched_literal?}"
          end
        end

        # Update state and dictionary
        # XZ Utils dict_put pattern:
        # dict->buf[dict->pos++] = byte;
        # if (!dict->has_wrapped)
        #     dict->full = dict->pos - LZ_DICT_INIT_POS;
        @state.update_literal
        warn "DEBUG: After update_literal - state=#{@state.value}" if ENV["LZMA_DEBUG"]

        # Write to dictionary buffer at current position
        # XZ Utils dict_put pattern: dict->buf[dict->pos++] = byte;
        # DEBUG: Check byte value at critical position
        if @pos == 576 + 256
          XzUtilsDecoderDebug.debug_puts "DEBUG: Storing byte at pos 832 (256th decoded byte)"
          XzUtilsDecoderDebug.debug_puts "  byte.class=#{byte.class}"
          XzUtilsDecoderDebug.debug_puts "  byte=#{byte}"
          XzUtilsDecoderDebug.debug_puts "  byte.ord=#{byte.is_a?(String) ? byte.ord : 'N/A (not a string)'}"
          XzUtilsDecoderDebug.debug_puts "  Integer value=#{byte.is_a?(Integer) ? byte : byte.ord}"
        end
        @dict_buf[@pos] = byte
        # DEBUG: Track array size changes
        if ENV["LZMA_DEBUG_ARRAY_WRITE"] && @dict_buf.size != (@dict_size + LZ_DICT_INIT_POS)
          XzUtilsDecoderDebug.debug_puts "DEBUG: Array expanded! pos=#{@pos}, byte=#{byte}, old_size=#{@dict_buf.size - 1}, new_size=#{@dict_buf.size}, decoder_id=#{@decoder_id}"
          XzUtilsDecoderDebug.debug_puts "  Writing beyond original size caused expansion!"
        end
        if ENV["LZMA_DEBUG_ARRAY_WRITE"]
          XzUtilsDecoderDebug.debug_puts "DEBUG write[#{@decoder_id}]: pos=#{@pos}, byte=#{byte}, dict_buf.size=#{@dict_buf.size}, dict_buf.object_id=#{@dict_buf.object_id}, nil_count=#{@dict_buf.count(nil)}"
        end
        if ENV["LZMA_DEBUG_ARRAY"]
          # Verify the write succeeded
          if @dict_buf[@pos] != byte
            raise "DEBUG after write: @dict_buf[#{@pos}] = #{@dict_buf[@pos].inspect}, expected #{byte}! nil_count=#{@dict_buf.count(nil)}"
          end
          if @dict_full.positive? && @pos > LZ_DICT_INIT_POS && @dict_buf[@pos - 1].nil?
            raise "DEBUG after write: @dict_buf[#{@pos - 1}] is nil! @pos=#{@pos}, @dict_full=#{@dict_full}"
          end
        end
        @pos += 1

        # ARM64 DEBUG: Trace first 20 bytes being written to dictionary
        if ENV["TRACE_ARM64_BYTES"]
          @arm64_trace ||= []
          if @arm64_trace.size < 20
            @arm64_trace << [@dict_full, @pos, byte.class,
                             byte.is_a?(Integer) ? byte : byte.ord, @dict_buf[@pos]]
            if @arm64_trace.size == 20
              # Dump the trace
              puts "\n=== ARM64 BYTE TRACE (first 20 bytes) ==="
              puts "Decoder ID: #{@decoder_id}"
              @arm64_trace.each_with_index do |entry, i|
                df, p, _, val, stored = entry
                puts "  [#{i + 1}] dict_full=#{df.to_s.rjust(6)}, pos=#{p.to_s.rjust(6)}, byte=#{val.to_s.rjust(3)} (0x#{val.to_s(16).upcase.rjust(
                  2, '0'
                )}) stored=#{stored.inspect}"
              end
              puts "=========================================\n"
              $stderr.flush
            end
          end
        end

        # Update dict_full (XZ Utils pattern)
        # When dict_full reaches dict_size, the dictionary is full
        # After that, dict_full stays at dict_size and has_wrapped = true
        unless @has_wrapped
          @dict_full = @pos - LZ_DICT_INIT_POS
          # Check if we've reached the maximum dictionary size
          if @dict_full >= @dict_size
            @has_wrapped = true
            @dict_full = @dict_size
          end
        end

        # Track bytes decoded in this chunk (for match length limiting)
        # IMPORTANT: Always increment this, even after dictionary wraps!
        # This is needed for correct match length limiting when @uncompressed_size is set.
        # XZ Utils uses dict.limit for this, but we use @chunk_bytes_decoded.
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          @chunk_bytes_decoded += 1
        end

        # DEBUG: Show literal decode for position 220-230
        if old_dict_full.between?(220, 230)
          XzUtilsDecoderDebug.debug_puts "\n=== decode_literal at dict_full=#{old_dict_full} ==="
          XzUtilsDecoderDebug.debug_puts "  Decoded: 0x#{byte.to_s(16)} ('#{byte.chr}')"
          XzUtilsDecoderDebug.debug_puts "  rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end
      end

      # Decode a match
      #
      # SDK decoding sequence:
      # 1. Decode is_rep bit
      # 2. If regular match:
      #    - Decode match length using length coder
      #    - Decode match distance using distance coder
      # 3. If rep match:
      #    - Decode which rep distance to use (rep0/1/2/3)
      #    - Decode rep match length
      # 4. Check for EOS marker
      # 5. Copy matched data from dictionary
      # 6. Update state machine and rep distances
      # 7. Update dictionary and position
      #
      # @return [Boolean] True if EOS marker detected, false otherwise
      def decode_match
        pos_state = @pos & ((1 << @pb) - 1)

        # DEEP DEBUG: Trace every detail at position 227
        if ENV["LZMA_DEBUG"] && @dict_full == 227
          puts "\n=== DEEP DEBUG at dict_full=227 ==="
          puts "  State: #{@state.value}, pos_state=#{pos_state}"
          puts "  Rep distances BEFORE: (#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
          puts "  Range decoder: range=0x#{@range_decoder.range.to_s(16).upcase}, code=0x#{@range_decoder.code.to_s(16).upcase}"
          input_buffer = @range_decoder.instance_variable_get(:@input)
          puts "  Input buffer: #{input_buffer ? input_buffer.size : 'nil'} bytes"
        end

        # Decode is_rep bit
        is_rep_model = @is_rep_models[@state.value]
        if ENV["TRACE_IS_REP"]
          range_val = @range_decoder.range
          code_val = @range_decoder.code
          puts "[XzUtilsDecoder.decode_match] Before is_rep: state.value=#{@state.value}"
          puts "  is_rep_model.object_id=#{is_rep_model.object_id}, prob=#{is_rep_model.probability}"
          puts "  range=#{range_val} (0x#{range_val.to_s(16)}), code=#{code_val} (0x#{code_val.to_s(16)})"
          bound_calc = (range_val >> 11) * is_rep_model.probability
          puts "  bound=(#{range_val} >> 11) * #{is_rep_model.probability} = #{bound_calc} (0x#{bound_calc.to_s(16)})"
          puts "  code < bound? #{code_val < bound_calc}"
        end
        is_rep = @range_decoder.decode_bit(is_rep_model)

        if ENV["TRACE_IS_REP"]
          range_val = @range_decoder.range
          code_val = @range_decoder.code
          puts "[XzUtilsDecoder.decode_match] Decoded is_rep=#{is_rep} with prob=#{is_rep_model.probability}"
          puts "  After is_rep: range=#{range_val} (0x#{range_val.to_s(16)}), code=#{code_val} (0x#{code_val.to_s(16)})"
        end

        if ENV["LZMA_DEBUG"] && @dict_full == 227
          puts "  Decoded is_rep bit: #{is_rep} (#{@is_rep_models[@state.value].probability})"
          puts "  After is_rep: range=0x#{@range_decoder.range.to_s(16).upcase}, code=0x#{@range_decoder.code.to_s(16).upcase}"
        end

        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_match START - is_rep=#{is_rep}, state.value=#{@state.value}, pos_state=#{pos_state}, rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        if is_rep.zero?
          # Regular match (not rep)
          if ENV["LZMA_DEBUG"] && @dict_full.between?(220, 240)
            puts "DEBUG pos #{@dict_full}: Regular match (not rep)"
          end
          # Return result from decode_regular_match (true if EOS marker detected)
          return true if decode_regular_match(pos_state)
        else
          # Rep match - decode which rep distance to use
          if ENV["LZMA_DEBUG"] && @dict_full.between?(220, 240)
            puts "DEBUG pos #{@dict_full}: Rep match (is_rep=1)"
          end
          decode_rep_match(pos_state)
        end

        false # No EOS marker detected
      end

      # Decode a regular (non-rep) match
      #
      # XZ Utils dict_repeat pattern (from lz_decoder.h:203-263):
      # - Validate distance: dict->full > distance
      # - Calculate back = dict->pos - distance - 1
      # - If distance >= dict->pos: back += dict->size - LZ_DICT_REPEAT_MAX
      # - Copy bytes from back position
      # - Update dict->full if !has_wrapped
      #
      # @param pos_state [Integer] Position state
      # @return [Boolean] True if EOS marker detected, false otherwise
      def decode_regular_match(pos_state)
        # DEBUG: Trace matches around dict_full = 60-63
        old_dict_full = @dict_full
        old_rep0 = @rep0
        old_state = @state.value

        # Decode match length
        length_encoded = @length_coder.decode(@range_decoder,
                                              pos_state)
        length = length_encoded + MATCH_LEN_MIN

        # Calculate length state for distance decoding
        # XZ Utils formula (from lzma_common.h get_dist_state macro):
        # ((len) < DIST_STATES + MATCH_LEN_MIN ? (len) - MATCH_LEN_MIN : DIST_STATES - 1)
        # This gives: len=2→0, len=3→1, len=4→2, len=5→3, len=6+→3
        len_state = if length < NUM_LEN_TO_POS_STATES + MATCH_LEN_MIN
                      length - MATCH_LEN_MIN
                    else
                      NUM_LEN_TO_POS_STATES - 1
                    end

        # DEBUG: Show bytes being copied
        if old_dict_full.between?(210, 230) || ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "\n=== decode_regular_match at dict_full=#{old_dict_full} ===" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER] decode_regular_match at dict_full=#{old_dict_full}" if ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "  pos_state=#{pos_state}" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER]   pos_state=#{pos_state}" if ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "  state=#{old_state}" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER]   state=#{old_state}" if ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "  length_encoded=#{length_encoded} length=#{length}" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER]   length_encoded=#{length_encoded} length=#{length}" if ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "  len_state=#{len_state}" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER]   len_state=#{len_state}" if ENV["LZMA_DEBUG_DISTANCE"]
          XzUtilsDecoderDebug.debug_puts "  rep0_before=#{old_rep0}" if old_dict_full.between?(
            210, 230
          )
          puts "[DISTANCE_DECODER]   rep0_before=#{old_rep0}" if ENV["LZMA_DEBUG_DISTANCE"]
        end

        if ENV["LZMA_DEBUG"] && old_dict_full.between?(220, 230)
          puts "DEBUG decode_regular_match at dict_full=#{old_dict_full}: length=#{length}"
        end

        # Decode match distance
        # XZ Utils stores distance in rep0 without +1
        # The distance coder returns 0-based distance
        rep0 = @distance_coder.decode(@range_decoder, len_state)

        # DEBUG
        if (ENV.fetch("LZMA_DEBUG",
                      nil) && old_dict_full.between?(210,
                                                     230)) || old_dict_full == 293
          puts "  rep0_decoded=#{rep0} (distance = #{rep0})"
          puts "  buffer_back calculation: back=#{@dict_full - rep0 - 1}"
        end
        if ENV["LZMA_DEBUG"] && rep0 > 100000
          puts "  [LARGE_DISTANCE at dict_full=#{old_dict_full}] rep0=#{rep0}, call count=#{$distance_decode_count || 'unknown'}"
        end

        # Check for SDK EOS marker FIRST (before validation)
        # EOS marker: rep0 == UINT32_MAX (0xFFFFFFFF)
        # XZ Utils checks: if (rep0 == UINT32_MAX) goto eopm;
        # EOPM is only allowed if @allow_eopm is true OR uncompressed_size is unknown
        # Reference: XZ Utils lzma_decoder.c:697-705, 874-888
        if rep0 == 0xFFFFFFFF
          if @allow_eopm || @uncompressed_size == 0xFFFFFFFFFFFFFFFF
            # XZ Utils pattern after detecting EOPM:
            # 1. Normalize range decoder (may read more input bytes)
            # 2. Check if range decoder is finished (code == 0)
            # Reference: lzma_decoder.c:881-887 (SEQ_EOPM case)
            @range_decoder.normalize

            # Check if range decoder is finished (code == 0)
            unless @range_decoder.code.zero?
              raise Omnizip::DecompressionError,
                    "EOPM detected but range decoder not finished (code=#{@range_decoder.code}). Corrupted stream."
            end

            return true # EOS marker detected, stop decoding
          else
            raise Omnizip::DecompressionError,
                  "End-of-payload marker (EOPM) detected but not allowed (LZMA2 streams cannot have EOPM)"
          end
        end

        # Validate distance using XZ Utils dict_is_distance_valid pattern
        # XZ Utils: lzma_decoder.c:876 - dict_is_distance_valid(&dict, rep0)
        # See lz_decoder.h:194-198: return dict->full > distance;
        # XZ Utils dict->full = dict->pos - LZ_DICT_INIT_POS (same as our @dict_full)
        # The distance is valid if: dict->full > distance
        unless @dict_full > rep0
          raise Omnizip::DecompressionError,
                "Invalid distance: #{rep0} (dict_full: #{@dict_full})"
        end

        # Additional validation: ensure distance doesn't exceed absolute dictionary size
        # Only validate against absolute dictionary size to prevent buffer overflow
        # The wrapping logic (below) handles rep0 >= @dict_full cases
        if rep0 > @dict_size + @dict_full
          raise Omnizip::DecompressionError,
                "Invalid distance: #{rep0} exceeds maximum possible (dict_size=#{@dict_size}, dict_full=#{@dict_full})"
        end

        # IMPORTANT: Limit match length to not exceed uncompressed_size
        # XZ Utils handles this by setting dict.limit and checking before each write
        # We need to ensure we don't exceed the target size
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          # Calculate how many bytes we can still decode in THIS chunk
          # @chunk_bytes_decoded is the bytes decoded in this chunk (starts from 0)
          # @uncompressed_size is the target for THIS chunk (not cumulative)
          remaining = @uncompressed_size - @chunk_bytes_decoded
          if length > remaining
            if ENV["LZMA_DEBUG"] || remaining <= 5
              puts "DEBUG: Limiting match length from #{length} to #{remaining} (chunk_bytes_decoded=#{@chunk_bytes_decoded}, uncompressed_size=#{@uncompressed_size}, dict_full=#{@dict_full})"
            end
            length = remaining
          end
        end

        # Copy matched data from dictionary using XZ Utils dict_repeat pattern
        # See lz_decoder.h:211-213:
        # back = dict->pos - distance - 1;
        # if (distance >= dict->pos)
        #     back += dict->size - LZ_DICT_REPEAT_MAX;
        #
        # Note: dict->pos in XZ Utils is the actual data position (same as our @dict_full)
        # Our @pos includes the LZ_DICT_INIT_POS offset, so we use @dict_full for calculations
        #
        # dict->size in XZ Utils = dict_size + 2 * LZ_DICT_REPEAT_MAX
        # Our dict_buf size = @dict_size + LZ_DICT_INIT_POS = @dict_size + 2 * LZ_DICT_REPEAT_MAX
        back = @dict_full - rep0 - 1
        if rep0 >= @dict_full
          # Distance wraps to the end of the dictionary buffer
          # XZ Utils: back += dict->size - LZ_DICT_REPEAT_MAX;
          # Our dict_buf size = @dict_size + LZ_DICT_INIT_POS = @dict_size + 2 * LZ_DICT_REPEAT_MAX
          # So: back += (@dict_size + 2 * LZ_DICT_REPEAT_MAX) - LZ_DICT_REPEAT_MAX
          #    = back + @dict_size + LZ_DICT_REPEAT_MAX
          back += @dict_size + LZ_DICT_REPEAT_MAX
        end
        # Convert to buffer position (add LZ_DICT_INIT_POS offset)
        buffer_back = back + LZ_DICT_INIT_POS

        # DEBUG: Show buffer position for position 217
        if old_dict_full.between?(210, 230)
          XzUtilsDecoderDebug.debug_puts "  buffer_back=#{buffer_back}, back=#{back}"
          bytes_at_back = @dict_buf[buffer_back, 3]
          bytes_hex = if bytes_at_back.is_a?(String)
                        bytes_at_back.bytes.map do |b|
                          "%02x" % b
                        end.join(" ")
                      else
                        bytes_at_back.map do |b|
                          "%02x" % b
                        end.join(" ")
                      end
          XzUtilsDecoderDebug.debug_puts "  First 3 bytes at buffer_back: #{bytes_hex} (#{bytes_at_back.inspect})"
        end

        if ENV["LZMA_DEBUG"]
          b0 = @dict_buf[buffer_back]
          b1 = @dict_buf[buffer_back + 1]
          b2 = @dict_buf[buffer_back + 2]
          b0_str = b0 ? "0x#{b0.to_s(16).upcase}" : "nil"
          b1_str = b1 ? "0x#{b1.to_s(16).upcase}" : "nil"
          b2_str = b2 ? "0x#{b2.to_s(16).upcase}" : "nil"
          b0_chr = b0 ? "'#{b0.chr}'" : "nil"
          b1_chr = b1 ? "'#{b1.chr}'" : "nil"
          b2_chr = b2 ? "'#{b2.chr}'" : "nil"
          warn "DEBUG: copy from buffer_back=#{buffer_back} (distance #{rep0}): #{b0_str} (#{b0_chr}) #{b1_str} (#{b1_chr}) #{b2_str} (#{b2_chr})"
          warn "DEBUG: pos_before=#{@pos} (output #{@pos - LZ_DICT_INIT_POS}), len=#{length}, pos_after=#{@pos + length} (output #{@pos + length - LZ_DICT_INIT_POS})"
          # Show what the dictionary contains at key positions (simplified)
          warn "DEBUG: dict_buf size=#{@dict_buf.size}, allocated=#{@dict_size + 608}"
        end

        # Copy bytes from dictionary and extend buffer as needed
        # XZ Utils dict_repeat pattern: dict->buf[dict->pos++] = dict->buf[back++]
        if ENV["LZMA_DEBUG"] && old_dict_full.between?(220, 260)
          puts "  Copying #{length} bytes from buffer_back=#{buffer_back} to @pos=#{@pos}, dict_full=#{@dict_full}"
          puts "  Source bytes: #{@dict_buf[buffer_back, length].inspect}"
          puts "  First 5 target bytes before copy: #{@dict_buf[@pos,
                                                                5].inspect}"
        end
        length.times do |i|
          byte = @dict_buf[buffer_back + i]
          if ENV["LZMA_DEBUG"]
            warn "DEBUG: copy iteration #{i}: reading dict_buf[#{buffer_back + i}]=0x#{byte.to_s(16).upcase} ('#{byte.chr}'), writing to dict_buf[#{@pos + i}]"
          end
          @dict_buf[@pos + i] = byte
          if ENV["LZMA_DEBUG_ARRAY_WRITE"] && @dict_buf.size != (@dict_size + LZ_DICT_INIT_POS)
            XzUtilsDecoderDebug.debug_puts "DEBUG: Array expanded during copy! write_pos=#{@pos + i}, byte=#{byte}, old_size=#{@dict_buf.size - 1}, new_size=#{@dict_buf.size}, decoder_id=#{@decoder_id}"
          end
        end
        if ENV["LZMA_DEBUG"] && old_dict_full.between?(220, 230)
          puts "  After copy: #{@dict_buf[@pos, length].inspect}"
        end

        # Update state and position
        @state.update_match
        warn "DEBUG: After update_match - state=#{@state.value}" if ENV["LZMA_DEBUG"]
        @pos += length

        # Update dict_full (XZ Utils pattern)
        # When dict_full reaches dict_size, the dictionary is full
        # After that, dict_full stays at dict_size and has_wrapped = true
        unless @has_wrapped
          @dict_full = @pos - LZ_DICT_INIT_POS
          # Check if we've reached the maximum dictionary size
          if @dict_full >= @dict_size
            @has_wrapped = true
            @dict_full = @dict_size
          end
        end

        # Track bytes decoded in this chunk (for match length limiting)
        # IMPORTANT: Increment by length for match copies (multiple bytes at once)
        # This is needed for correct match length limiting when @uncompressed_size is set.
        # XZ Utils uses dict.limit for this, but we use @chunk_bytes_decoded.
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          @chunk_bytes_decoded += length
        end

        # Update rep distances - rotate and set new rep0
        # SDK rotation: rep3←rep2, rep2←rep1, rep1←rep0, rep0←rep0
        # XZ Utils stores the actual distance in rep0 (no +1)
        if ENV["LZMA_DEBUG"]
          warn "DEBUG: Before rotation - rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3}), new distance=#{rep0}"
        end

        # DEBUG: Trace rep rotation for position 224
        if ENV["LZMA_DEBUG"] && old_dict_full.between?(220, 230)
          puts "\n=== Rep rotation after match at dict_full=#{old_dict_full} ==="
          puts "  Before: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
          puts "  Setting rep0 to: #{rep0.inspect}"
        end

        @rep3 = @rep2
        @rep2 = @rep1
        @rep1 = @rep0
        @rep0 = rep0

        if ENV["LZMA_DEBUG"]
          warn "DEBUG: After rotation - rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # DEBUG: Show final rep values
        if ENV["LZMA_DEBUG"] && old_dict_full.between?(220, 230)
          puts "  After: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # DEBUG: Verify rep0 is actually set
        if old_dict_full.between?(220, 230)
          actual_rep0 = @rep0
          XzUtilsDecoderDebug.debug_puts "  VERIFICATION: @rep0=#{actual_rep0.inspect}, @rep0.object_id=#{@rep0.object_id}"
        end

        # DEBUG: Trace range/code state after match at dict_full 56-62
        if ENV.fetch("LZMA_DEBUG",
                     nil) && old_dict_full >= 56 && old_dict_full <= 62
          range_after = @range_decoder.instance_variable_get(:@range)
          code_after = @range_decoder.instance_variable_get(:@code)
          XzUtilsDecoderDebug.debug_puts "  AFTER match (dict_full #{old_dict_full}→#{@dict_full}): range=0x#{range_after.to_s(16).upcase}, code=0x#{code_after.to_s(16).upcase}"
        end

        false # Not EOS, continue decoding
      end

      # Decode a rep match
      #
      # SDK rep match decoding (from XZ Utils lzma_decoder.c):
      # - is_rep0: Use rep0
      #   - is_rep0_long=0: Short rep (length=1, don't rotate)
      #   - is_rep0_long=1: Long rep (decode length, keep rep0)
      # - is_rep1: Use rep1, rotate rep1→rep0
      # - is_rep2: Use rep2, rotate rep2→rep0
      # - Otherwise: Use rep3, rotate rep3→rep0
      # After rotation, rep0 always contains the actual distance to use
      #
      # @param pos_state [Integer] Position state
      # @return [Boolean] Always false (rep matches are never EOS)
      def decode_rep_match(pos_state)
        # DEBUG: Trace rep matches around position 217
        old_dict_full = @dict_full
        old_rep0 = @rep0

        # DEBUG: Show rep distances at the start
        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_rep_match START[#{@decoder_id}] - rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # DEBUG: Trace rep matches around position 227
        if old_dict_full.between?(220, 230)
          XzUtilsDecoderDebug.debug_puts "\n=== decode_rep_match at dict_full=#{old_dict_full} (decoder_id=#{@decoder_id}) ==="
          XzUtilsDecoderDebug.debug_puts "  At START: rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
          XzUtilsDecoderDebug.debug_puts "  old_rep0=#{old_rep0} (captured @rep0)"
          XzUtilsDecoderDebug.debug_puts "  @rep0.object_id=#{@rep0.object_id}"
        end

        # Decode which rep distance to use
        is_rep0 = @range_decoder.decode_bit(@is_rep0_models[@state.value])

        puts "DEBUG rep match selection at dict_full=#{@dict_full}: is_rep0=#{is_rep0}, rep0/1/2/3 before=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})" if @dict_full.between?(
          220, 230
        )
        puts "  state.value=#{@state.value}, pos_state=#{pos_state}, model_index=#{(@state.value * (1 << @pb)) + pos_state}" if @dict_full.between?(
          220, 230
        )

        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_rep_match - is_rep0=#{is_rep0}"
        end

        if is_rep0.zero?
          # Use rep0
          puts "DEBUG rep match using rep0" if @dict_full.between?(220, 230)
          # XZ Utils: is_rep0_long[state][pos_state] where the array size is NUM_STATES * (1 << pb)
          is_rep0_long = @range_decoder.decode_bit(
            @is_rep0_long_models[(@state.value * (1 << @pb)) + pos_state],
          )

          if ENV["LZMA_DEBUG"]
            warn "DEBUG: decode_rep_match - is_rep0_long=#{is_rep0_long}"
          end

          if is_rep0_long.zero?
            # Short rep (length=1)
            length = 1
            @state.update_short_rep
          else
            # Long rep with rep0
            length = @rep_length_coder.decode(@range_decoder,
                                              pos_state) + MATCH_LEN_MIN
            @state.update_rep
          end
        else
          # Not rep0, check rep1/rep2/rep3
          puts "DEBUG rep match NOT using rep0 (is_rep0=#{is_rep0})" if @dict_full.between?(
            220, 230
          )

          is_rep1 = @range_decoder.decode_bit(@is_rep1_models[@state.value])

          if is_rep1.zero?
            # Use rep1 - XZ Utils pattern:
            # const uint32_t distance = rep1;
            # rep1 = rep0;
            # rep0 = distance;
            @rep1, @rep0 = @rep0, @rep1
          else
            # Not rep1, check rep2/rep3
            is_rep2 = @range_decoder.decode_bit(@is_rep2_models[@state.value])

            if is_rep2.zero?
              # Use rep2 - XZ Utils pattern:
              # const uint32_t distance = rep2;
              # rep2 = rep1;
              # rep1 = rep0;
              # rep0 = distance;
              distance = @rep2
            else
              # Use rep3 - XZ Utils pattern:
              # const uint32_t distance = rep3;
              # rep3 = rep2;
              # rep2 = rep1;
              # rep1 = rep0;
              # rep0 = distance;
              distance = @rep3
              @rep3 = @rep2
            end
            @rep2 = @rep1
            @rep1 = @rep0
            @rep0 = distance
          end

          # Decode length for rep1/2/3
          length = @rep_length_coder.decode(@range_decoder,
                                            pos_state) + MATCH_LEN_MIN
          @state.update_rep
        end

        # After rotation, rep0 always contains the distance to use
        # XZ Utils stores distances without +1 offset
        distance = @rep0

        puts "DEBUG rep match after rotation: dict_full=#{old_dict_full}, distance=#{distance}, rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})" if old_dict_full.between?(
          220, 230
        )

        # DEBUG: Trace rep matches around position 217
        if old_dict_full.between?(210, 230)
          XzUtilsDecoderDebug.debug_puts "\n=== decode_rep_match at dict_full=#{old_dict_full} ==="
          XzUtilsDecoderDebug.debug_puts "  old_rep0=#{old_rep0}, new rep0=#{@rep0} (distance=#{distance})"
          XzUtilsDecoderDebug.debug_puts "  pos_state=#{pos_state}"
        end

        if ENV["LZMA_DEBUG"]
          warn "DEBUG: decode_rep_match - length=#{length}, distance=#{distance}, dict_full=#{@dict_full}, rep0/1/2/3=(#{@rep0},#{@rep1},#{@rep2},#{@rep3})"
        end

        # Validate distance using XZ Utils dict_is_distance_valid pattern
        # See lz_decoder.h:194-198: return dict->full > distance;
        # Note: distance=0 is valid (means copy from position 0, the first byte)
        # XZ Utils allows distance=0 as long as dict->full > 0 (at least one byte available)
        unless @dict_full > distance
          raise "Invalid rep distance: #{distance} (dict_full: #{@dict_full})"
        end

        # IMPORTANT: Limit match length to not exceed uncompressed_size
        # XZ Utils handles this by setting dict.limit and checking before each write
        # We need to ensure we don't exceed the target size
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          # Calculate how many bytes we can still decode in THIS chunk
          # @chunk_bytes_decoded is the bytes decoded in this chunk (starts from 0)
          # @uncompressed_size is the target for THIS chunk (not cumulative)
          remaining = @uncompressed_size - @chunk_bytes_decoded
          if length > remaining
            if ENV["LZMA_DEBUG"] || remaining <= 5
              puts "DEBUG REP: Limiting rep match length from #{length} to #{remaining} (chunk_bytes_decoded=#{@chunk_bytes_decoded}, uncompressed_size=#{@uncompressed_size}, dict_full=#{@dict_full})"
            end
            length = remaining
          end
        end

        # Copy matched data from dictionary using XZ Utils dict_repeat pattern
        # back = dict->pos - distance - 1;
        # if (distance >= dict->pos) back += dict->size - LZ_DICT_REPEAT_MAX;
        #
        # Note: dict->pos in XZ Utils is the actual data position (same as our @dict_full)
        # Our @pos includes the LZ_DICT_INIT_POS offset, so we use @dict_full for calculations
        #
        # dict->size in XZ Utils = dict_size + 2 * LZ_DICT_REPEAT_MAX
        # Our dict_buf size = @dict_size + LZ_DICT_INIT_POS = @dict_size + 2 * LZ_DICT_REPEAT_MAX
        back = @dict_full - distance - 1
        old_back = back
        if distance >= @dict_full
          # Distance wraps to the end of the dictionary buffer
          # XZ Utils: back += dict->size - LZ_DICT_REPEAT_MAX;
          # Our dict_buf size = @dict_size + LZ_DICT_INIT_POS = @dict_size + 2 * LZ_DICT_REPEAT_MAX
          # So: back += (@dict_size + 2 * LZ_DICT_REPEAT_MAX) - LZ_DICT_REPEAT_MAX
          #    = back + @dict_size + LZ_DICT_REPEAT_MAX
          back += @dict_size + LZ_DICT_REPEAT_MAX
        end
        # Convert to buffer position (add LZ_DICT_INIT_POS offset)
        buffer_back = back + LZ_DICT_INIT_POS

        puts "DEBUG rep match copy at dict_full=#{@dict_full}: @dict_full=#{@dict_full}, distance=#{distance}, back=#{back}, buffer_back=#{buffer_back}" if @dict_full.between?(
          220, 230
        )

        # DEBUG: Show back calculation for position 217
        if old_dict_full.between?(210, 230)
          XzUtilsDecoderDebug.debug_puts "  back calculation: @dict_full=#{@dict_full}, distance=#{distance}"
          XzUtilsDecoderDebug.debug_puts "  back=#{old_back}, wrapped_back=#{back}, buffer_back=#{buffer_back}"
          bytes_at_back = @dict_buf[buffer_back, 3]
          bytes_hex = if bytes_at_back.is_a?(String)
                        bytes_at_back.bytes.map do |b|
                          "%02x" % b
                        end.join(" ")
                      else
                        [bytes_at_back].flatten.map do |b|
                          "%02x" % b
                        end.join(" ")
                      end
          XzUtilsDecoderDebug.debug_puts "  First 3 bytes at buffer_back: #{bytes_hex} (#{bytes_at_back.inspect})"
        end

        # Copy bytes from dictionary and extend buffer as needed
        # XZ Utils dict_repeat pattern: dict->buf[dict->pos++] = dict->buf[back++]
        if old_dict_full.between?(250, 260)
          source_val = @dict_buf[@pos - 1]
          puts "  Rep match copy at dict_full=#{@dict_full}: length=#{length}, distance=#{distance}, @pos=#{@pos} (will write to #{@pos}...#{@pos + length - 1})"
          puts "  Reading from @pos-1=#{@pos - 1}, source byte = #{source_val} (0x#{source_val.to_s(16)} '#{begin
            source_val.chr
          rescue StandardError
            '?'
          end}')"
          puts "  Before copy: @dict_buf[#{@pos}...#{@pos + length - 1}] = #{@dict_buf[@pos,
                                                                                       length].inspect}"
        end
        length.times do |i|
          byte = @dict_buf[buffer_back + i]
          if @dict_full == 227 && i.zero?
            puts "DEBUG dict_copy at dict_full=227, i=0:"
            puts "  buffer_back=#{buffer_back}, byte=#{byte} ('#{byte.chr}')"
            puts "  Writing to @pos=#{@pos + i}"
            puts "  dict_buf[buffer_back...buffer_back+10] = #{@dict_buf[buffer_back,
                                                                         10].inspect}"
            # DEBUG: Check if buffer_back+1 has the correct byte
            puts "  dict_buf[buffer_back+1=#{buffer_back + 1}] = #{@dict_buf[buffer_back + 1].inspect} ('#{begin
              @dict_buf[buffer_back + 1].chr
            rescue StandardError
              '?'
            end}')"
            prev_5 = if buffer_back > 4
                       @dict_buf[(buffer_back - 5)..(buffer_back - 1)].map do |b|
                         "0x#{b.to_s(16).upcase} (#{b.chr})"
                       end.join(", ")
                     else
                       "N/A"
                     end
            puts "  Previous 5 bytes: [#{prev_5}]"
            puts "  Current dict_full=#{@dict_full}, @pos=#{@pos}"
          end
          @dict_buf[@pos + i] = byte
        end

        # Update position
        @pos += length

        # Update dict_full (XZ Utils pattern)
        # When dict_full reaches dict_size, the dictionary is full
        # After that, dict_full stays at dict_size and has_wrapped = true
        unless @has_wrapped
          @dict_full = @pos - LZ_DICT_INIT_POS
          # Check if we've reached the maximum dictionary size
          if @dict_full >= @dict_size
            @has_wrapped = true
            @dict_full = @dict_size
          end
        end

        # Track bytes decoded in this chunk (for match length limiting)
        # IMPORTANT: Increment by length for match copies (multiple bytes at once)
        # This is needed for correct match length limiting when @uncompressed_size is set.
        # XZ Utils uses dict.limit for this, but we use @chunk_bytes_decoded.
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF
          @chunk_bytes_decoded += length
        end

        false # Rep matches are never EOS
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
      # the literal decoder can calculate the correct offset: 3 * context_value
      #
      # This creates (1 << (lc + lp)) unique contexts
      #
      # @return [Integer] Literal context value (unshifted, 0-7 for lc=3)
      def calculate_literal_state
        # XZ Utils dict_get0 pattern: dict->buf[dict->pos - 1]
        # For array buffer, use @pos - 1 as index

        # DEBUG: Check buffer state before access
        if ENV["LZMA_DEBUG_CALC_STATE"] && @dict_full == 8
          XzUtilsDecoderDebug.debug_puts "DEBUG before calc_state[#{@decoder_id}]: pos=#{@pos}, dict_full=#{@dict_full}"
          XzUtilsDecoderDebug.debug_puts "  @dict_buf.object_id=#{@dict_buf.object_id}, size=#{@dict_buf.size}"
          XzUtilsDecoderDebug.debug_puts "  Accessing index #{@pos - 1}: value=#{@dict_buf[@pos - 1].inspect}"
        end

        prev_byte = @dict_full.positive? ? @dict_buf[@pos - 1] : 0

        # Safeguard: if prev_byte is nil, use 0 and log detailed diagnostics
        # This can happen if the buffer was not properly initialized or we're accessing the wrong buffer
        if prev_byte.nil?
          if ENV["LZMA_DEBUG_NIL_BYTE"]
            raise "DEBUG: prev_byte is nil! decoder_id=#{@decoder_id}, @pos=#{@pos}, @dict_full=#{@dict_full}, @dict_buf.size=#{@dict_buf&.size || 'nil'}, accessing index #{@pos - 1}, nil_count=#{@dict_buf&.count(nil) || 'N/A'}, @dict_buf.object_id=#{@dict_buf&.object_id || 'nil'}"
          end

          prev_byte = 0
        end

        if ENV["LZMA_DEBUG_CALC_STATE"]
          XzUtilsDecoderDebug.debug_puts "DEBUG calc_state[#{@decoder_id}]: pos=#{@pos}, dict_full=#{@dict_full}, @dict_buf.object_id=#{@dict_buf.object_id}, prev_byte=#{prev_byte}"
        end

        # XZ Utils formula from lzma_common.h:literal_mask_calc
        # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
        # For lc=3, lp=0: (256 << 0) - (256 >> 3) = 256 - 32 = 224 (0xE0)
        literal_mask = (0x100 << @lp) - (0x100 >> @lc)

        # Combine dict_full (actual decoded position) and prev_byte, then apply mask
        # IMPORTANT: XZ Utils uses dict.pos (which starts at 0 and increments)
        # omnizip's @pos starts at LZ_DICT_INIT_POS (576), so we use @dict_full instead
        # This ensures we match XZ Utils's literal state calculation exactly
        (((@dict_full << 8) + prev_byte) & literal_mask)
      end
    end
  end
end
