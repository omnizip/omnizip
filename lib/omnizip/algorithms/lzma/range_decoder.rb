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

require_relative "range_coder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Range decoder for LZMA decompression
      #
      # This class implements the decoding side of arithmetic coding
      # using integer range arithmetic. It decodes bits from the
      # compressed byte stream based on their probability models.
      #
      # The decoder mirrors the encoder's range subdivisions to
      # extract the original bit values. It maintains a code value
      # that represents the current position within the range.
      class RangeDecoder < RangeCoder
        attr_reader :code

        # Initialize the range decoder
        #
        # @param input_stream [IO] The input stream of encoded bytes
        def initialize(input_stream)
          super
          @code = 0
          @initialization_complete = false
          @init_bytes_remaining = 5
          init_decoder
        end

        # Update the input stream (for LZMA2 multi-chunk streams)
        #
        # When processing LZMA2 chunks, we need to update the stream
        # reference for each new chunk while preserving the range decoder
        # state (range, code) across chunks.
        #
        # XZ Utils pattern: The range coder uses a buffer pointer that's
        # updated for each chunk, while rc_reset() resets range/code.
        #
        # @param new_stream [IO] New input stream
        # @return [void]
        def update_stream(new_stream)
          @stream = new_stream
        end

        # Decode a single bit using a probability model
        #
        # The range is split based on the bit's probability,
        # and the code value determines which portion contains
        # the actual bit value.
        #
        # XZ Utils pattern (rc_if_0): normalize BEFORE bound calculation
        # See: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_decoder.h:181-184
        #
        # @param model [BitModel] The probability model for this bit
        # @return [Integer] The decoded bit value (0 or 1)
        def decode_bit(model)
          # XZ Utils: rc_normalize FIRST, then calculate bound
          normalize
          bound = (@range >> 11) * model.probability

          # DEBUG: Trace model updates to find probability corruption
          trace_model_updates = ENV.fetch("TRACE_MODEL_UPDATES", nil)
          prob_before = model.probability if trace_model_updates

          # DEBUG: Trace is_rep bit decoding
          trace_is_rep = ENV.fetch("TRACE_IS_REP_BITS", nil) && (bound > 1_000_000)

          if trace_is_rep
            puts "  [RangeDecoder.decode_bit] BEFORE: range=#{@range}, code=#{@code}, bound=#{bound}, prob=#{model.probability}"
          end

          # DEBUG: Trace model selection at dict_full=227
          if ENV["TRACE_MODEL_SELECTION"]
            begin
              ObjectSpace.each_object(Omnizip::Algorithms::XzUtilsDecoder) do |decoder|
                dict_full = decoder.instance_variable_get(:@dict_full)
                if dict_full && dict_full >= 220 && dict_full <= 235
                  pos = decoder.instance_variable_get(:@pos)
                  state = decoder.instance_variable_get(:@state)
                  puts "    [decode_bit] dict_full=#{dict_full}, pos=#{pos}, state=#{state}"
                  puts "    [decode_bit] model.object_id=#{model.object_id}, prob=#{model.probability}"
                  puts "    [decode_bit] range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, bound=0x#{bound.to_s(16)}"
                  $stderr.flush
                end
                break
              end
            rescue StandardError => e
              # Context not available
              puts "    [decode_bit] ERROR: #{e.message}"
              $stderr.flush
            end
          end

          # DEBUG: Trace decode_bit for lit_state=96 literal decoding
          if ENV["TRACE_DECODE_BIT_LIT96"]
            puts "    decode_bit: range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, prob=#{model.probability}, bound=0x#{bound.to_s(16)}, code<bound?=#{@code < bound}"
          end

          # DEBUG: Trace decode_bit for specific problematic state
          if ENV.fetch("TRACE_SPECIFIC_DECODE", nil) && @range == 0x40000000 && @code == 0x21407d82
            puts "    === CRITICAL DECODE_BIT (MATCHED LITERAL) ==="
            puts "    BEFORE: range=0x#{@range.to_s(16)} (#{@range})"
            puts "    BEFORE: code=0x#{@code.to_s(16)} (#{@code})"
            puts "    probability=#{model.probability}"
            puts "    bound=0x#{bound.to_s(16)} (#{bound})"
            puts "    range >> 11 = 0x#{(@range >> 11).to_s(16)} (#{@range >> 11})"
            puts "    (range >> 11) * probability = 0x#{((@range >> 11) * model.probability).to_s(16)} (#{(@range >> 11) * model.probability})"
            puts "    code < bound? #{@code < bound}"
            puts "    result should be: #{@code < bound ? 0 : 1}"
            puts "    =========================================="
          end

          # DEBUG: Trace decode_bit for model_index=257 (the problematic one)
          if ENV["TRACE_DECODE_BIT_257"]
            # We need to know which model is being used
            # Unfortunately, we don't have direct access to the model_index here
            puts "    [decode_bit] range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, prob=#{model.probability}, bound=0x#{bound.to_s(16)}, code<bound?=#{@code < bound}, result=#{@code < bound ? 0 : 1}"
          end

          if @code < bound
            @range = bound
            model.update(0)
            if trace_model_updates && prob_before != model.probability
              puts "    [decode_bit] model UPDATE: #{prob_before} -> #{model.probability} (bit=0, object_id=#{model.object_id})"
            end
            if trace_is_rep
              puts "  [RangeDecoder.decode_bit] AFTER (bit=0): range=#{@range}, code=#{@code}"
            end
            0
          else
            @code -= bound
            @range -= bound
            model.update(1)
            if trace_model_updates && prob_before != model.probability
              puts "    [decode_bit] model UPDATE: #{prob_before} -> #{model.probability} (bit=1, object_id=#{model.object_id})"
            end
            if trace_is_rep
              puts "  [RangeDecoder.decode_bit] AFTER (bit=1): range=#{@range}, code=#{@code}"
            end
            1
          end
        end

        # Decode bits directly without using probability model
        #
        # This is used for decoding values with uniform distribution
        # where all bit values are equally likely.
        #
        # @param num_bits [Integer] Number of bits to decode
        # @return [Integer] The decoded value
        def decode_direct_bits(num_bits)
          result = 0
          trace_this = (num_bits == 25)
          iteration = 0

          if trace_this
            begin
              warn "    decode_direct_bits START: num_bits=#{num_bits}"
              warn "      BEFORE: range=#{@range.inspect}, code=#{@code.inspect}"
              $stderr.flush
            rescue StandardError => e
              warn "      ERROR in trace: #{e.message}"
              $stderr.flush
            end
          end

          begin
            num_bits.downto(1) do |_i|
              iteration += 1
              normalize
              @range >>= 1

              bit = @code >= @range ? 1 : 0
              if trace_this && iteration <= 3 # Only first 3 iterations
                warn "      [#{iteration}/#{num_bits}] range=#{@range.inspect}, code=#{@code.inspect}, bit=#{bit}, result=#{result}"
                $stderr.flush
              end

              if bit == 1
                @code -= @range
                result = (result << 1) | 1
              else
                result = (result << 1) | 0
              end
            end
          rescue StandardError => e
            warn "      ERROR in iteration #{iteration}: #{e.message}"
            warn "      range=#{@range.inspect}, code=#{@code.inspect}"
            $stderr.flush
            raise
          end

          if trace_this
            warn "      AFTER #{iteration} iterations: result=#{result}"
            $stderr.flush
          end

          result
        end

        # Decode a cumulative frequency value
        #
        # This is used by PPMd for decoding symbols based on their
        # frequency distribution. Returns the cumulative frequency
        # that can be mapped back to a symbol.
        #
        # @param total_freq [Integer] Total frequency of all symbols in context
        # @return [Integer] The cumulative frequency value
        def decode_freq(total_freq)
          normalize
          range_freq = @range / total_freq
          @code / range_freq
        end

        # Normalize after decoding a symbol with frequency
        #
        # After using decode_freq to get the cumulative frequency,
        # call this to update the range decoder state.
        #
        # @param cum_freq [Integer] Cumulative frequency of decoded symbol
        # @param freq [Integer] Frequency of decoded symbol
        # @param total_freq [Integer] Total frequency of all symbols
        # @return [void]
        def normalize_freq(cum_freq, freq, total_freq)
          range_freq = @range / total_freq
          low_bound = range_freq * cum_freq
          high_bound = range_freq * (cum_freq + freq)

          @code -= low_bound
          @range = (high_bound - low_bound) & 0xFFFFFFFF
        end

        # Decode bits directly using a base value (XZ Utils rc_direct pattern)
        #
        # This method implements the XZ Utils rc_direct macro which is used
        # for decoding distance values in slots 14+. The pattern matches
        # XZ Utils' implementation in rangecoder/range_decoder.h:366-375.
        #
        # XZ Utils rc_direct behavior (from C macro):
        # - dest = (dest << 1) + 1 (unconditionally)
        # - Normalize range, halve it, subtract from code
        # - bound = 0 - (code >> 31) extracts sign bit
        #   - If code >= range (bit=1): sign=0, bound=0, dest stays at (dest << 1) + 1
        #   - If code < range (bit=0): sign=1, bound=-1, dest = (dest << 1) + 1 - 1 = dest << 1
        # - dest += bound
        # - code += range & bound (restore code if bit=0)
        #
        # In Ruby (without unsigned wraparound), we explicitly check if code >= range
        # and undo the +1 if the bit is 0.
        #
        # @param num_bits [Integer] Number of bits to decode
        # @param base [Integer] Base value to start from (2 or 3 for distances)
        # @return [Integer] The decoded value
        def decode_direct_bits_with_base(num_bits, base)
          result = base
          # DEBUG: Trace for slot=40 (num_bits=15)
          if ENV["TRACE_DIRECT_BITS_SLOT40"]
            puts "      [decode_direct_bits_with_base] START: base=#{base}, num_bits=#{num_bits}"
            puts "        BEFORE: range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}"
          end
          num_bits.times do |i|
            result = (result << 1) + 1
            normalize
            @range >>= 1

            # Check if bit is 1 before modifying @code
            # If code >= range, bit is 1; otherwise bit is 0
            bit = @code >= @range ? 1 : 0

            if ENV["TRACE_DIRECT_BITS_SLOT40"] && i < 15
              puts "        [#{i + 1}/#{num_bits}] bit=#{bit}, result after this step = #{result - (bit.zero? ? 1 : 0)}, range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}"
            end

            if bit == 1
              # Bit is 1: result stays at (result << 1) + 1
              @code -= @range
            else
              # Bit is 0: undo the +1, result = (result << 1) + 1 - 1 = result << 1
              result -= 1
            end
          end
          if ENV["TRACE_DIRECT_BITS_SLOT40"]
            puts "        [decode_direct_bits_with_base] END: result=#{result}"
          end
          result
        end

        # Reset the range decoder for a new chunk
        #
        # This matches XZ Utils rc_reset() behavior:
        # - Reset range to UINT32_MAX (0xFFFFFFFF)
        # - Reset code to 0
        # - Set init_bytes_remaining to 5 (lazy initialization)
        # - Let normalize() read the initialization bytes during actual decoding
        #
        # Called during state reset (control >= 0xA0) to reset the range decoder
        # for the new chunk's compressed data.
        #
        # XZ Utils reference: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_decoder.h:181
        #
        # @return [void]
        def reset
          if ENV["LZMA_DEBUG"]
            stream_pos = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            warn "      RangeDecoder.reset: BEFORE reset, range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, stream.pos=#{stream_pos}, init_bytes_remaining=#{@init_bytes_remaining}"
          end
          @range = 0xFFFFFFFF
          @code = 0
          # Lazy initialization: set remaining bytes but don't read yet
          # normalize() will read these bytes during actual decoding
          @init_bytes_remaining = 5
          if ENV["LZMA_DEBUG"]
            stream_pos_after = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            warn "      RangeDecoder.reset: AFTER reset, code=0x#{@code.to_s(16)}, stream.pos=#{stream_pos_after}, init_bytes_remaining=#{@init_bytes_remaining}"
          end
        end

        # Normalize the range when it becomes too small
        #
        # When range drops below TOP threshold, shift in a new
        # byte from the input stream and scale up the range by 256.
        #
        # XZ Utils pattern (rc_normalize): uses IF, not WHILE!
        # Each normalize call shifts in at most ONE byte.
        # See: /Users/mulgogi/src/external/xz/src/liblzma/rangecoder/range_decoder.h:143-149
        #
        # XZ Utils lazy initialization (range_decoder.h:146-149):
        # If init_bytes_remaining > 0, read byte for code initialization
        # Otherwise, read byte for range normalization
        #
        # @return [void]
        def normalize
          # DEBUG: Trace normalize calls
          if @init_bytes_remaining.positive?
            stream_pos_before = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            stream_size = begin
              @stream.size
            rescue StandardError
              "N/A"
            end
          end

          # XZ Utils: Handle lazy initialization first
          # IMPORTANT: Read ALL initialization bytes in a loop, not just one!
          # XZ Utils rc_normalize reads one byte per call, but decode_bit only calls
          # normalize once at the start, so we need to loop to read all 5 bytes.
          while @init_bytes_remaining.positive?
            byte = @stream.getbyte
            byte ||= 0
            code_before = @code
            @code = ((code_before << 8) | byte) & 0xFFFFFFFF
            @init_bytes_remaining -= 1

            if ENV["RANGE_DECODER_TRACE"]
              puts "\n=== RangeDecoder.normalize (init_bytes_remaining=#{@init_bytes_remaining + 1}) ==="
              puts "  stream_pos_before=#{stream_pos_before}, stream_size=#{stream_size}"
              puts "  byte=0x#{byte.to_s(16).upcase}, code_before=0x#{code_before.to_s(16).upcase}"
              puts "  (code_before << 8) = 0x#{(code_before << 8).to_s(16).upcase}"
              puts "  ((code_before << 8) | byte) = 0x#{((code_before << 8) | byte).to_s(16).upcase}"
              puts "  code_after=0x#{@code.to_s(16).upcase}"
            end
          end

          if @range < TOP
            byte = read_byte
            @range <<= 8
            @code = ((@code << 8) | byte) & 0xFFFFFFFF
            if ENV["RANGE_DECODER_TRACE"]
              pos = begin
                @stream.pos
              rescue StandardError
                "N/A"
              end
              warn "      NORMALIZE: pos=#{pos}, byte=0x#{byte.to_s(16).upcase}, code=0x#{@code.to_s(16).upcase}, range=0x#{@range.to_s(16).upcase}"
              $stderr.flush
            end
          end
        end

        private

        # Initialize the decoder by reading the first bytes
        #
        # XZ Utils rc_read_init (range_decoder.h:160-167):
        # - Read 5 bytes and construct code value
        # - code is uint32_t, so it's automatically masked to 32 bits
        # - In Ruby, we need to explicitly mask to ensure 32-bit value
        #
        # @return [void]
        def init_decoder
          5.times do
            @code = ((@code << 8) | read_byte) & 0xFFFFFFFF
            @init_bytes_remaining -= 1 if @init_bytes_remaining.positive?
          end
          @initialization_complete = true
        end

        # Read a single byte from the input stream
        #
        # @return [Integer] The byte value (0-255)
        # @raise [Omnizip::DecompressionError] If stream is exhausted during normal decoding
        def read_byte
          byte = @stream.getbyte

          # During normal decoding (after initialization), if we run out of input,
          # this indicates corrupted data - the compressed stream ended prematurely
          if byte.nil? && @initialization_complete && @init_bytes_remaining.zero?
            raise Omnizip::DecompressionError,
                  "LZMA compressed data exhausted prematurely. The file may be corrupted or the uncompressed size field may be incorrect."
          end

          # Only track as data byte if initialization is complete
          if @initialization_complete && @init_bytes_remaining.zero?
            pos = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            if ENV["RANGE_DECODER_TRACE"]
              warn "      READ_BYTE: pos=#{pos.inspect}, byte=0x#{byte.to_s(16).upcase}"
              $stderr.flush
            end
            if ENV["LZMA_DEBUG"]
              warn "      READ_BYTE: pos=#{pos.inspect}, byte=0x#{byte.to_s(16).upcase}, @code now=0x#{@code.to_s(16)}"
            end
          end

          byte || 0
        end
      end
    end
  end
end
