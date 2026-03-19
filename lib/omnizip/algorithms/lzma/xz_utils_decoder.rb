# frozen_string_literal: true

require "stringio"

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

      # Maximum dictionary size to prevent memory exhaustion
      # 64MB is a reasonable practical limit
      MAX_DICT_SIZE = 64 * 1024 * 1024

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

      # Map a monotonic position to a circular buffer index.
      # Buffer layout: [LZ_DICT_INIT_POS zero bytes] + [dict_size circular region]
      # @pos grows forever; this maps it to the fixed-size buffer.
      # Matches C++ 7-Zip SDK: dic[dicPos] with dicPos wrapping at dicBufSize.
      def dict_index(pos)
        LZ_DICT_INIT_POS + ((pos - LZ_DICT_INIT_POS) % @dict_size)
      end

      # Flush decoded output from the circular dictionary buffer.
      # Copies bytes from @flush_pos to @pos into the output stream or accumulator.
      # Handles wrap-around when the data spans the circular buffer boundary.
      def flush_circular_output(output)
        return if @pos == @flush_pos

        length = @pos - @flush_pos

        if length > @dict_size
          raise Omnizip::DecompressionError,
                "Internal error: flush lag (#{length}) exceeds dict_size (#{@dict_size})"
        end

        start_idx = dict_index(@flush_pos)
        buf_end = @buf_end

        if start_idx + length <= buf_end
          # No wrap
          data = @dict_buf.byteslice(start_idx, length)
        else
          # Wraps around the circular boundary
          first_len = buf_end - start_idx
          data = @dict_buf.byteslice(start_idx, first_len)
          data << @dict_buf.byteslice(LZ_DICT_INIT_POS, length - first_len)
        end

        if output
          output.write(data.force_encoding(Encoding::BINARY))
        else
          @output_accumulator ||= StringIO.new("".b)
          @output_accumulator.write(data)
        end

        @flush_pos = @pos
      end

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
          @dict_size = [[options.fetch(:dict_size), 1].max, MAX_DICT_SIZE].min
          @uncompressed_size = options.fetch(:uncompressed_size)
        else
          # Standalone LZMA file - read header from input
          read_header
        end

        validate_parameters
        init_models
        init_coders

        # Cache computed values for hot loop
        @pb_mask = (1 << @pb) - 1
        @pb_shift = 1 << @pb
        @literal_mask = (0x100 << @lp) - (0x100 >> @lc)
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

        # Create range decoder if it doesn't exist (first chunk)
        # This happens when the decoder is created directly for LZMA (not LZMA2)
        unless @range_decoder
          @range_decoder = RangeDecoder.new(@input)
        end

        # Special case: empty input (uncompressed_size == 0)
        # Return immediately without trying to decode anything
        if @uncompressed_size != 0xFFFFFFFFFFFFFFFF && @uncompressed_size.zero?
          return "" # Empty output
        end

        @debug_iter = 0

        # Track bytes decoded in this chunk (for multi-chunk streams)
        # This is needed to limit match lengths correctly when @uncompressed_size
        # represents only the current chunk's size, not the total size
        @chunk_bytes_decoded = 0

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
        if @dict_buf.nil?
          @buf_end = LZ_DICT_INIT_POS + @dict_size
          buf_size = @buf_end
          @dict_buf = ("\0" * buf_size).b
          @pos = LZ_DICT_INIT_POS
          @dict_pos = LZ_DICT_INIT_POS  # Circular buffer write position (tracks @pos)
          @dict_full = 0
          @has_wrapped = false

          # Add preloaded data to dictionary (from LZMA2 uncompressed chunks)
          # This must be done before decoding so matches can reference this data
          if @preloaded_data && !@preloaded_data.empty?
            idx = @dict_pos
            buf_end = @buf_end
            @preloaded_data.each_byte do |byte|
              @dict_buf.setbyte(idx, byte)
              @pos += 1
              idx += 1
              idx = LZ_DICT_INIT_POS if idx >= buf_end
            end
            @dict_pos = idx
            # Update dict_full to reflect preloaded data
            @dict_full = @pos - LZ_DICT_INIT_POS
            @preloaded_data = nil # Clear after loading
          end
        end

        # Track starting position for multi-chunk streams
        # IMPORTANT: Calculate start_pos AFTER dictionary initialization!
        # This ensures that preloaded data (from LZMA2 uncompressed chunks) is
        # properly reflected in start_pos, so we only return NEW bytes.
        # For LZMA2, we need to return only the NEW bytes, not all bytes from LZ_DICT_INIT_POS
        start_pos = @pos || LZ_DICT_INIT_POS

        # Initialize rep distances (XZ Utils initializes to 0)
        # See: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:1054-1055
        # For LZMA2 multi-chunk streams, rep distances persist across chunks
        # Only reset when not preserving dictionary (first chunk)
        #
        # IMPORTANT: Initialize rep distances if they're nil OR not preserving dict
        if @rep0.nil? || @rep1.nil? || @rep2.nil? || @rep3.nil? || !preserve_dict
          @rep0 = 0
          @rep1 = 0
          @rep2 = 0
          @rep3 = 0
        end

        # Read range decoder init bytes (must happen after set_input sets correct stream)
        if @range_decoder.respond_to?(:read_init_bytes) && @range_decoder.init_bytes_remaining.positive?
          @range_decoder.read_init_bytes
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

        # Circular buffer: no growth needed. Buffer is fixed at dict_size + LZ_DICT_INIT_POS.
        # Output is flushed incrementally when the circular position nears wrap point.
        # Matches C++ 7-Zip SDK: dic is pre-allocated to dicBufSize and never resized.
        @flush_pos = @pos
        @output_accumulator = output.nil? ? StringIO.new("".b) : nil

        iteration = 0
        loop do
          iteration += 1
          # Check if we've reached the expected size (if known)
          # XZ Utils: checks dict.pos < dict.limit

          # Handle nil @pos or limit gracefully
          if limit && (@pos.nil? || limit.nil?)
            raise "Invalid state: @pos=#{@pos.inspect}, limit=#{limit.inspect}"
          end

          # Circular buffer: flush output before it can be overwritten.
          # LZMA matches are at most 273 bytes, so flush when within 273 of wrapping.
          if @pos - @flush_pos > @dict_size - 273
            flush_circular_output(output)
          end

          # Decode is_match bit
          pos_state = @pos & @pb_mask
          # XZ Utils: is_match[state][pos_state] where the array is NUM_STATES * (1 << pb)
          # The array stride changes with pb value
          model_index = (@state.value * @pb_shift) + pos_state

          @debug_iter += 1

          is_match = @range_decoder.decode_bit(@is_match_models[model_index])

          if is_match.zero?
            # Decode literal
            decode_literal
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
              # XZ Utils pattern (lzma_decoder.c): when STREAM_END is reached,
              # reset the range coder for the next chunk. This happens even for
              # no-reset chunks (control 0x80-0x9F) - the range coder is ALWAYS
              # re-initialized between chunks, only state/dict/models are preserved.
              @range_decoder.reset
              break
            elsif @range_decoder.code.zero?
              # EOPM is allowed (e.g., LZMA_Alone format)
              # If range decoder is finished, we're done
              # XZ Utils: rc_reset at STREAM_END
              @range_decoder.reset
              break
              # Otherwise, continue decoding to find EOPM marker
              # XZ Utils sets eopm_is_valid = true and continues
              # Reference: lzma_decoder.c:704
            end
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

        # Flush remaining output from the circular buffer
        flush_circular_output(output)

        # Return output
        if output
          @pos - start_pos
        else
          @output_accumulator.string.force_encoding(Encoding::BINARY)
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
        # Update properties if provided
        properties_changed = !!(new_lc || new_lp || new_pb)
        @lc = new_lc if new_lc
        @lp = new_lp if new_lp
        @pb = new_pb if new_pb

        # Recompute cached values when properties change
        if properties_changed
          @pb_mask = (1 << @pb) - 1
          @pb_shift = 1 << @pb
          @literal_mask = (0x100 << @lp) - (0x100 >> @lc)
        end

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
        @range_decoder&.reset

        # Reinitialize probability models (XZ Utils lines 1064-1082)
        # IMPORTANT: Use reset_models (reset in place) instead of init_models (create new)
        # for state reset only. Only create new models when properties change.
        if properties_changed
          init_models
        else
          reset_models
        end

        # Reinitialize coders (needed for pb changes)
        # Only recreate coders when properties have changed
        init_coders if properties_changed

        # Reset dictionary position and full count (XZ Utils pattern)
        # Only reset if preserve_dict is false
        unless preserve_dict
          # Reinitialize dictionary buffer
          # XZ Utils allocates a new buffer for each dictionary reset
          @dict_buf = ("\0" * (@dict_size + LZ_DICT_INIT_POS)).b
          @pos = LZ_DICT_INIT_POS
          @dict_pos = LZ_DICT_INIT_POS
          @dict_full = 0
          @has_wrapped = false
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
        # Reset state machine (XZ Utils line 1053)
        @state = SdkStateMachine.new

        # Reset rep distances (XZ Utils lines 1054-1057)
        @rep0 = 0
        @rep1 = 0
        @rep2 = 0
        @rep3 = 0

        # Reset probability models (XZ Utils init_temporals for control >= 0xA0)
        reset_models

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
        # Reset state machine only (XZ Utils line 1053)
        @state = SdkStateMachine.new

        # Reset probability models (XZ Utils init_temporals for control >= 0xA0)
        reset_models

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
        @range_decoder&.reset
      end

      def reset_state_only
        # Complete state reset requires both prepare and finish phases
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

        # Create range decoder if it doesn't exist (first chunk)
        if @range_decoder.nil?
          @range_decoder = RangeDecoder.new(@input)
        else
          # Update the range decoder's input stream to the new input
          # This is needed because RangeDecoder holds a reference to the stream
          @range_decoder.update_stream(@input)
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
        idx = @dict_pos
        buf_end = @buf_end
        data.each_byte do |byte|
          @dict_buf.setbyte(idx, byte)
          @pos += 1
          idx += 1
          idx = LZ_DICT_INIT_POS if idx >= buf_end
        end
        @dict_pos = idx

        # Update dict_full to reflect new data
        unless @has_wrapped
          @dict_full = @pos - LZ_DICT_INIT_POS
          if @dict_full >= @dict_size
            @has_wrapped = true
            @dict_full = @dict_size
          end
        end
      end

      # No-op: circular buffer has fixed size, no compaction needed.
      # Kept for API compatibility — LZMA2 decoder calls this between chunks.
      def compact_buffer; end

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

        # Clamp dict_size to prevent memory exhaustion
        @dict_size = [[@dict_size, 1].max, MAX_DICT_SIZE].min

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
        # Calculate literal state using SDK formula
        lit_state = calculate_literal_state

        # Decode literal (matched or unmatched)
        # Check if dictionary has any valid bytes (XZ Utils: dict->full > 0)
        if @state.use_matched_literal? && @dict_full.positive?
          # Matched literal: use match byte from dictionary at distance rep0
          # XZ Utils dict_get pattern: dict->buf[dict->pos - distance - 1]
          match_byte = @dict_buf.getbyte(dict_index(@pos - @rep0 - 1))
          byte = @literal_decoder.decode_matched(match_byte, lit_state, @lc,
                                                 @range_decoder, @literal_models)
        else
          # Unmatched literal: simple 8-bit decoding
          byte = @literal_decoder.decode_unmatched(lit_state, @lc,
                                                   @range_decoder, @literal_models)
        end

        # Update state and dictionary
        # XZ Utils dict_put pattern:
        # dict->buf[dict->pos++] = byte;
        # if (!dict->has_wrapped)
        #     dict->full = dict->pos - LZ_DICT_INIT_POS;
        @state.update_literal

        # Write to dictionary buffer at current position
        # XZ Utils dict_put pattern: dict->buf[dict->pos++] = byte;
        @dict_buf.setbyte(@dict_pos, byte)
        @pos += 1
        @dict_pos += 1
        @dict_pos = LZ_DICT_INIT_POS if @dict_pos >= @buf_end

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
        pos_state = @pos & @pb_mask

        # Decode is_rep bit
        is_rep_model = @is_rep_models[@state.value]
        is_rep = @range_decoder.decode_bit(is_rep_model)

        if is_rep.zero?
          # Regular match (not rep)
          # Return result from decode_regular_match (true if EOS marker detected)
          return true if decode_regular_match(pos_state)
        else
          # Rep match - decode which rep distance to use
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
        # Decode match length
        length_encoded = @length_coder.decode(@range_decoder, pos_state)
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

        # Decode match distance
        # XZ Utils stores distance in rep0 without +1
        # The distance coder returns 0-based distance
        rep0 = @distance_coder.decode(@range_decoder, len_state)

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

        # Validate distance: ensure we have enough bytes in the buffer.
        # In this linear buffer model, @pos grows unbounded across chunks while
        # @dict_full is clamped at @dict_size. Use actual bytes written for validation.
        actual_bytes_written = @pos - LZ_DICT_INIT_POS
        unless actual_bytes_written > rep0
          raise Omnizip::DecompressionError,
                "Invalid distance: #{rep0} (bytes_written: #{actual_bytes_written})"
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
        # Linear buffer: use @pos directly for back reference
        # @pos always points to the next write position, so @pos - rep0 - 1
        # gives the correct source position for the match copy
        buffer_back = @pos - rep0 - 1

        # Copy bytes from dictionary and extend buffer as needed
        # XZ Utils dict_repeat pattern: dict->buf[dict->pos++] = dict->buf[back++]
        src_idx = dict_index(buffer_back)
        dst_idx = @dict_pos
        buf_end = @buf_end
        length.times do
          byte = @dict_buf.getbyte(src_idx)
          @dict_buf.setbyte(dst_idx, byte)
          src_idx += 1
          src_idx = LZ_DICT_INIT_POS if src_idx >= buf_end
          dst_idx += 1
          dst_idx = LZ_DICT_INIT_POS if dst_idx >= buf_end
        end
        @dict_pos = dst_idx

        # Update state and position
        @state.update_match
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
        @rep3 = @rep2
        @rep2 = @rep1
        @rep1 = @rep0
        @rep0 = rep0

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
        # Decode which rep distance to use
        is_rep0 = @range_decoder.decode_bit(@is_rep0_models[@state.value])

        if is_rep0.zero?
          # Use rep0
          # XZ Utils: is_rep0_long[state][pos_state] where the array size is NUM_STATES * (1 << pb)
          is_rep0_long = @range_decoder.decode_bit(
            @is_rep0_long_models[(@state.value * @pb_shift) + pos_state],
          )

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

        # Validate distance: ensure we have enough bytes in the buffer.
        # In this linear buffer model, @pos grows unbounded across chunks while
        # @dict_full is clamped at @dict_size. Use actual bytes written for validation.
        actual_bytes_written = @pos - LZ_DICT_INIT_POS
        unless actual_bytes_written > distance
          raise "Invalid rep distance: #{distance} (bytes_written: #{actual_bytes_written})"
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
        # Linear buffer: use @pos directly for back reference
        buffer_back = @pos - distance - 1

        # Copy bytes from dictionary
        # XZ Utils dict_repeat pattern: dict->buf[dict->pos++] = dict->buf[back++]
        src_idx = dict_index(buffer_back)
        dst_idx = @dict_pos
        buf_end = @buf_end
        length.times do
          byte = @dict_buf.getbyte(src_idx)
          @dict_buf.setbyte(dst_idx, byte)
          src_idx += 1
          src_idx = LZ_DICT_INIT_POS if src_idx >= buf_end
          dst_idx += 1
          dst_idx = LZ_DICT_INIT_POS if dst_idx >= buf_end
        end
        @dict_pos = dst_idx

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
        prev_idx = @dict_pos == LZ_DICT_INIT_POS ? @buf_end - 1 : @dict_pos - 1
        prev_byte = @dict_full.positive? ? @dict_buf.getbyte(prev_idx) : 0

        # Safeguard: if prev_byte is nil, use 0
        prev_byte = 0 if prev_byte.nil?

        # Combine current output position and prev_byte, then apply cached mask.
        # XZ Utils uses dict.pos (continuous write position) for this calculation.
        # We use @pos - LZ_DICT_INIT_POS (total bytes decoded) instead of @dict_full,
        # because @dict_full is clamped at @dict_size after the circular buffer wraps,
        # which would freeze the position-dependent literal model selection.
        output_pos = @pos - LZ_DICT_INIT_POS
        ((output_pos << 8) + prev_byte) & @literal_mask
      end
    end
  end
end
