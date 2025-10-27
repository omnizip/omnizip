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

require_relative "model"
require_relative "../lzma/range_encoder"

module Omnizip
  module Algorithms
    class PPMd7 < Algorithm
      # PPMd7 Encoder using range coding
      #
      # Encodes a stream of bytes using the PPMd7 prediction
      # model combined with range encoding for arithmetic coding.
      class Encoder
        attr_reader :model

        # Initialize the encoder
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :model_order Maximum context order
        # @option options [Integer] :mem_size Memory size for model
        def initialize(output, options = {})
          @output = output
          @model = Model.new(
            options[:model_order] || Model::DEFAULT_ORDER,
            options[:mem_size] || Model::DEFAULT_MEM_SIZE
          )
          @range_encoder = LZMA::RangeEncoder.new(output)
        end

        # Encode a stream of bytes
        #
        # Reads from input, compresses using PPMd7 model,
        # and writes to output stream.
        #
        # @param input [IO] Input stream to compress
        # @return [void]
        def encode_stream(input)
          while (byte = input.getbyte)
            encode_symbol(byte)
          end

          # Flush encoder
          @range_encoder.flush
        end

        private

        # Encode a single symbol using the model
        #
        # Uses the model to get probability information and
        # encodes using range coding. Handles escapes if symbol
        # is not in current context.
        #
        # @param symbol [Integer] The byte to encode (0-255)
        # @return [void]
        def encode_symbol(symbol)
          prob = @model.get_symbol_probability(symbol)

          encode_range(
            prob[:cumulative_freq],
            prob[:freq],
            prob[:total_freq]
          )
          if prob[:escape]
            # Encode escape and try shorter context
            # Recursively encode in shorter context
            encode_with_escape(symbol)
          else
            # Encode symbol directly
          end

          # Update model
          @model.update(symbol)
        end

        # Encode with escape handling
        #
        # When a symbol isn't in the current context, we encode
        # an escape and retry with a shorter context.
        #
        # @param symbol [Integer] Symbol to encode
        # @return [void]
        def encode_with_escape(symbol)
          # Try encoding in root context (always succeeds)
          # This is a simplified version - full PPMd would
          # walk through progressively shorter contexts
          root_prob = get_root_probability(symbol)
          encode_range(
            root_prob[:cumulative_freq],
            root_prob[:freq],
            root_prob[:total_freq]
          )
        end

        # Get probability from root context
        #
        # The root context always contains all symbols.
        #
        # @param symbol [Integer] Symbol to look up
        # @return [Hash] Probability information
        def get_root_probability(symbol)
          context = @model.root_context
          state = context.find_symbol(symbol)

          cum_freq = 0
          context.states.each do |sym, st|
            break if sym >= symbol

            cum_freq += st.freq
          end

          {
            cumulative_freq: cum_freq,
            freq: state.freq,
            total_freq: context.total_freq
          }
        end

        # Encode a range for the symbol
        #
        # Converts probability to range and encodes using the
        # range encoder.
        #
        # @param cum_freq [Integer] Cumulative frequency
        # @param freq [Integer] Symbol frequency
        # @param total_freq [Integer] Total frequency
        # @return [void]
        def encode_range(cum_freq, freq, total_freq)
          # Scale to range coder scale
          scale = 0x10000
          low = (cum_freq * scale) / total_freq
          high = ((cum_freq + freq) * scale) / total_freq

          # Encode using direct bits for simplicity
          # Full implementation would use proper range subdivision
          (high - low).bit_length
          @range_encoder.encode_direct_bits(low, 16)
        end
      end
    end
  end
end
