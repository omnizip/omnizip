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
    class LZMA
      # Raw LZMA1 stream encoder (one continuous range-coded stream
      # with the end-of-stream marker), reusing the XZ Utils symbol
      # coders. This is the payload for the legacy .lzma container
      # and the lzip member body.
      class Lzma1Encoder < Implementations::XZUtils::LZMA2::Encoder
        UINT32_MAX = 0xFFFFFFFF
        REPS = 4

        # Encode `input` as a complete standalone LZMA1 stream,
        # terminated by the end-of-stream marker (dist = 0xFFFFFFFF,
        # length 2) so decoders that do not know the size can stop.
        #
        # @param input [String]
        # @param emit_eopm [Boolean] omit when the container carries
        #   the uncompressed size (the legacy .lzma form)
        # @return [String] binary stream
        # rubocop:disable-next Metrics/MethodLength
        def encode(input, emit_eopm: true)
          @match_finder.reset
          output_buffer = StringIO.new
          output_buffer.set_encoding(Encoding::BINARY)
          encoder = XzRangeEncoder.new(output_buffer)
          @match_finder.feed(input)
          @match_finder.skip(@match_finder.buffer.bytesize)

          start_pos = 0
          @current_start_pos = start_pos
          pos = 0
          while pos < input.bytesize
            encode_queued_symbols(encoder, output_buffer)

            match_pos = start_pos + pos
            distance, length = @optimal.find_optimal(
              match_pos, @match_finder, @state, @state.reps, @models
            )

            if distance == UINT32_MAX || length == 1
              encode_literal(input.getbyte(pos), encoder, match_pos)
              pos += 1
            elsif distance < REPS
              encode_repeated_match(distance, length, encoder, match_pos,
                                    match_pos)
              pos += length
            else
              encode_match(distance - REPS, length, encoder, match_pos,
                           match_pos, input)
              pos += length
            end
          end

          encode_eopm(encoder, output_buffer, input.bytesize) if emit_eopm
          encode_queued_symbols(encoder, output_buffer)
          encoder.queue_flush
          encode_queued_symbols(encoder, output_buffer)
          output_buffer.string
        end

        private

        # End-of-stream marker: a normal match header with
        # dist0 = 0xFFFFFFFF and length 2. The distance slot is 63,
        # whose 30 footer bits the parent's distance coder emits as
        # 26 direct bits + the 4 align bits.
        def encode_eopm(encoder, output_buffer, total_pos)
          pos_state = total_pos & ((1 << @pb) - 1)
          encoder.queue_bit(@models.is_match[@state.value][pos_state], 1)
          encoder.queue_bit(@models.is_rep[@state.value], 0)
          @state.update_match!(UINT32_MAX)
          encode_match_length(2, pos_state, encoder)
          # Slot 63's 30 footer bits plus the length/header symbols
          # exceed the 53-slot symbol queue in one go.
          encode_queued_symbols(encoder, output_buffer)
          encode_distance(UINT32_MAX + 1, 2, encoder)
        end
      end
    end
  end
end
