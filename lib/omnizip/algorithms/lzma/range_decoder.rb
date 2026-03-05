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
        attr_reader :code, :init_bytes_remaining

        # Initialize the range decoder
        #
        # @param input_stream [IO] The input stream of encoded bytes
        def initialize(input_stream)
          super
          @code = 0
          @initialization_complete = false
          @init_bytes_remaining = 5

          # Cache ENV lookups once at initialization (ENV[] is a getenv() syscall)
          @trace_model_updates = ENV.fetch("TRACE_MODEL_UPDATES", nil)
          @trace_is_rep = ENV.fetch("TRACE_IS_REP_BITS", nil)
          @trace_model_selection = ENV.fetch("TRACE_MODEL_SELECTION", nil)
          @trace_decode_bit_lit96 = ENV.fetch("TRACE_DECODE_BIT_LIT96", nil)
          @trace_specific_decode = ENV.fetch("TRACE_SPECIFIC_DECODE", nil)
          @trace_decode_bit257 = ENV.fetch("TRACE_DECODE_BIT_257", nil)
          @range_decoder_trace = ENV.fetch("RANGE_DECODER_TRACE", nil)

          @trace_direct_bits = ENV.fetch("TRACE_DIRECT_BITS_SLOT40", nil)
          # Combined flag: true if ANY debug flag is set in decode_bit
          @any_decode_bit_debug = @trace_model_updates || @trace_is_rep ||
            @trace_model_selection || @trace_decode_bit_lit96 ||
            @trace_specific_decode || @trace_decode_bit257

          init_decoder
        end

        # Update the input stream (for LZMA2 multi-chunk streams)
        #
        # @param new_stream [IO] New input stream
        # @return [void]
        def update_stream(new_stream)
          @stream = new_stream
        end

        # Decode a single bit using a probability model
        #
        # This is the hottest method (~5 billion calls for a 600MB file).
        # normalize() and model.update() are inlined to eliminate method dispatch.
        # Debug checks use a single combined flag to minimize branching.
        #
        # @param model [BitModel] The probability model for this bit
        # @return [Integer] The decoded bit value (0 or 1)
        def decode_bit(model)
          # Inline normalize: only the hot path (range < TOP check)
          # Init bytes are handled eagerly in reset(), not here
          if @range < 0x01000000
            @range <<= 8
            @code = ((@code << 8) | (@stream.getbyte || 0)) & 0xFFFFFFFF
          end

          prob = model.probability
          bound = (@range >> 11) * prob

          # All debug checks behind a single flag
          if @any_decode_bit_debug
            prob_before = prob if @trace_model_updates

            trace_is_rep = @trace_is_rep && (bound > 1_000_000)

            if trace_is_rep
              puts "  [RangeDecoder.decode_bit] BEFORE: range=#{@range}, code=#{@code}, bound=#{bound}, prob=#{prob}"
            end

            if @trace_model_selection
              begin
                ObjectSpace.each_object(Omnizip::Algorithms::XzUtilsDecoder) do |decoder|
                  dict_full = decoder.instance_variable_get(:@dict_full)
                  if dict_full && dict_full >= 220 && dict_full <= 235
                    pos = decoder.instance_variable_get(:@pos)
                    state = decoder.instance_variable_get(:@state)
                    puts "    [decode_bit] dict_full=#{dict_full}, pos=#{pos}, state=#{state}"
                    puts "    [decode_bit] model.object_id=#{model.object_id}, prob=#{prob}"
                    puts "    [decode_bit] range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, bound=0x#{bound.to_s(16)}"
                    $stderr.flush
                  end
                  break
                end
              rescue StandardError => e
                puts "    [decode_bit] ERROR: #{e.message}"
                $stderr.flush
              end
            end

            if @trace_decode_bit_lit96
              puts "    decode_bit: range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, prob=#{prob}, bound=0x#{bound.to_s(16)}, code<bound?=#{@code < bound}"
            end

            if @trace_specific_decode && @range == 0x40000000 && @code == 0x21407d82
              puts "    === CRITICAL DECODE_BIT (MATCHED LITERAL) ==="
              puts "    BEFORE: range=0x#{@range.to_s(16)} (#{@range})"
              puts "    BEFORE: code=0x#{@code.to_s(16)} (#{@code})"
              puts "    probability=#{prob}"
              puts "    bound=0x#{bound.to_s(16)} (#{bound})"
              puts "    range >> 11 = 0x#{(@range >> 11).to_s(16)} (#{@range >> 11})"
              puts "    (range >> 11) * probability = 0x#{((@range >> 11) * prob).to_s(16)} (#{(@range >> 11) * prob})"
              puts "    code < bound? #{@code < bound}"
              puts "    result should be: #{@code < bound ? 0 : 1}"
              puts "    =========================================="
            end

            if @trace_decode_bit257
              puts "    [decode_bit] range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, prob=#{prob}, bound=0x#{bound.to_s(16)}, code<bound?=#{@code < bound}, result=#{@code < bound ? 0 : 1}"
            end
          end

          if @code < bound
            @range = bound
            # Inline model.update(0): prob += (2048 - prob) >> 5
            model.probability = prob + ((2048 - prob) >> 5)
            if @any_decode_bit_debug
              if @trace_model_updates && prob_before != model.probability
                puts "    [decode_bit] model UPDATE: #{prob_before} -> #{model.probability} (bit=0, object_id=#{model.object_id})"
              end
              if trace_is_rep
                puts "  [RangeDecoder.decode_bit] AFTER (bit=0): range=#{@range}, code=#{@code}"
              end
            end
            0
          else
            @code -= bound
            @range -= bound
            # Inline model.update(1): prob -= prob >> 5
            model.probability = prob - (prob >> 5)
            if @any_decode_bit_debug
              if @trace_model_updates && prob_before != model.probability
                puts "    [decode_bit] model UPDATE: #{prob_before} -> #{model.probability} (bit=1, object_id=#{model.object_id})"
              end
              if trace_is_rep
                puts "  [RangeDecoder.decode_bit] AFTER (bit=1): range=#{@range}, code=#{@code}"
              end
            end
            1
          end
        end

        # Decode bits directly without using probability model
        #
        # @param num_bits [Integer] Number of bits to decode
        # @return [Integer] The decoded value
        def decode_direct_bits(num_bits)
          result = 0
          trace_this = XzUtilsDecoderDebug::ENABLED && (num_bits == 25)
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
              # Inline normalize
              if @range < 0x01000000
                @range <<= 8
                @code = ((@code << 8) | (@stream.getbyte || 0)) & 0xFFFFFFFF
              end
              @range >>= 1

              bit = @code >= @range ? 1 : 0
              if trace_this && iteration <= 3
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

        # Decode a cumulative frequency value (PPMd)
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
        # @param num_bits [Integer] Number of bits to decode
        # @param base [Integer] Base value to start from (2 or 3 for distances)
        # @return [Integer] The decoded value
        def decode_direct_bits_with_base(num_bits, base)
          result = base
          if @trace_direct_bits
            puts "      [decode_direct_bits_with_base] START: base=#{base}, num_bits=#{num_bits}"
            puts "        BEFORE: range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}"
          end
          num_bits.times do |i|
            result = (result << 1) + 1
            # Inline normalize
            if @range < 0x01000000
              @range <<= 8
              @code = ((@code << 8) | (@stream.getbyte || 0)) & 0xFFFFFFFF
            end
            @range >>= 1

            bit = @code >= @range ? 1 : 0

            if @trace_direct_bits && i < 15
              puts "        [#{i + 1}/#{num_bits}] bit=#{bit}, result after this step = #{result - (bit.zero? ? 1 : 0)}, range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}"
            end

            if bit == 1
              @code -= @range
            else
              result -= 1
            end
          end
          if @trace_direct_bits
            puts "        [decode_direct_bits_with_base] END: result=#{result}"
          end
          result
        end

        # Reset the range decoder for a new chunk
        #
        # Resets state only. Call read_init_bytes after the stream is set
        # to the correct input.
        #
        # @return [void]
        def reset
          if XzUtilsDecoderDebug::ENABLED
            stream_pos = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            warn "      RangeDecoder.reset: BEFORE reset, range=0x#{@range.to_s(16)}, code=0x#{@code.to_s(16)}, stream.pos=#{stream_pos}, init_bytes_remaining=#{@init_bytes_remaining}"
          end
          @range = 0xFFFFFFFF
          @code = 0
          @init_bytes_remaining = 5
        end

        # Eagerly read the 5 initialization bytes from the current stream.
        # Must be called after the stream is set to the correct input.
        #
        # @return [void]
        def read_init_bytes
          while @init_bytes_remaining.positive?
            byte = @stream.getbyte
            raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder initialization" if byte.nil?

            code_before = @code
            @code = ((code_before << 8) | byte) & 0xFFFFFFFF
            @init_bytes_remaining -= 1

            if @range_decoder_trace
              puts "\n=== RangeDecoder.normalize (init_bytes_remaining=#{@init_bytes_remaining + 1}) ==="
              puts "  byte=0x#{byte.to_s(16).upcase}, code_before=0x#{code_before.to_s(16).upcase}"
              puts "  code_after=0x#{@code.to_s(16).upcase}"
            end
          end

          if XzUtilsDecoderDebug::ENABLED
            stream_pos_after = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            warn "      RangeDecoder.reset: AFTER init, code=0x#{@code.to_s(16)}, stream.pos=#{stream_pos_after}, init_bytes_remaining=#{@init_bytes_remaining}"
          end
        end

        # Normalize the range when it becomes too small
        #
        # Still needed for decode_freq() and other non-hot paths.
        # The hot-path methods inline normalize directly.
        #
        # @return [void]
        def normalize
          # Handle lazy initialization if needed (for non-hot paths)
          if @init_bytes_remaining.positive?
            if @range_decoder_trace
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

            while @init_bytes_remaining.positive?
              byte = @stream.getbyte
              raise Omnizip::DecompressionError, "Truncated LZMA stream during range decoder initialization" if byte.nil?

              code_before = @code
              @code = ((code_before << 8) | byte) & 0xFFFFFFFF
              @init_bytes_remaining -= 1

              if @range_decoder_trace
                puts "\n=== RangeDecoder.normalize (init_bytes_remaining=#{@init_bytes_remaining + 1}) ==="
                puts "  stream_pos_before=#{stream_pos_before}, stream_size=#{stream_size}"
                puts "  byte=0x#{byte.to_s(16).upcase}, code_before=0x#{code_before.to_s(16).upcase}"
                puts "  (code_before << 8) = 0x#{(code_before << 8).to_s(16).upcase}"
                puts "  ((code_before << 8) | byte) = 0x#{((code_before << 8) | byte).to_s(16).upcase}"
                puts "  code_after=0x#{@code.to_s(16).upcase}"
              end
            end
          end

          if @range < TOP
            byte = read_byte
            @range <<= 8
            @code = ((@code << 8) | byte) & 0xFFFFFFFF
            if @range_decoder_trace
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

          if byte.nil? && @initialization_complete && @init_bytes_remaining.zero?
            raise Omnizip::DecompressionError,
                  "LZMA compressed data exhausted prematurely. The file may be corrupted or the uncompressed size field may be incorrect."
          end

          if @initialization_complete && @init_bytes_remaining.zero? && (@range_decoder_trace || XzUtilsDecoderDebug::ENABLED)
            pos = begin
              @stream.pos
            rescue StandardError
              "N/A"
            end
            if @range_decoder_trace
              warn "      READ_BYTE: pos=#{pos.inspect}, byte=0x#{byte.to_s(16).upcase}"
              $stderr.flush
            end
            if XzUtilsDecoderDebug::ENABLED
              warn "      READ_BYTE: pos=#{pos.inspect}, byte=0x#{byte.to_s(16).upcase}, @code now=0x#{@code.to_s(16)}"
            end
          end

          byte || 0
        end
      end
    end
  end
end
