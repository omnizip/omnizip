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
require_relative "../lzma/range_decoder"

module Omnizip
  module Algorithms
    class PPMd7 < Algorithm
      # PPMd7 Decoder using range coding
      #
      # Decodes a stream that was compressed with PPMd7 encoder.
      # Maintains synchronized model state with the encoder.
      class Decoder
        attr_reader :model

        # Initialize the decoder
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options
        # @option options [Integer] :model_order Maximum context order
        # @option options [Integer] :mem_size Memory size for model
        def initialize(input, options = {})
          @input = input
          @model = Model.new(
            options[:model_order] || Model::DEFAULT_ORDER,
            options[:mem_size] || Model::DEFAULT_MEM_SIZE,
          )
          @range_decoder = LZMA::RangeDecoder.new(input)
        end

        # Decode a stream back to original bytes
        #
        # Reads compressed data, decodes using PPMd7 model,
        # and returns the original data.
        #
        # @return [String] Decoded data
        def decode_stream
          result = String.new(encoding: Encoding::BINARY)

          # Simplified decoding - in practice would need proper
          # stream termination handling
          100.times do
            symbol = decode_symbol
            break if symbol.nil?

            result << symbol.chr
          end

          result
        end

        private

        # Decode a single symbol using the model
        #
        # Uses the model and range decoder to extract the
        # original symbol value.
        #
        # @return [Integer, nil] Decoded byte or nil if end
        def decode_symbol
          # Decode range value
          value = @range_decoder.decode_direct_bits(16)

          # Find symbol from range
          symbol = find_symbol_from_range(value)
          return nil if symbol.nil?

          # Update model to stay in sync with encoder
          @model.update(symbol)

          symbol
        end

        # Find symbol from decoded range value
        #
        # Converts the range value back to a symbol using
        # the current context's probability distribution.
        #
        # @param value [Integer] Decoded range value
        # @return [Integer, nil] The symbol
        def find_symbol_from_range(value)
          # This is simplified - real implementation would
          # properly decode using context probabilities
          context = @model.root_context

          # Find symbol whose cumulative range contains value
          scale = 0x10000
          cum_freq = 0

          context.states.keys.sort.each do |symbol|
            state = context.states[symbol]
            next_cum = cum_freq + state.freq
            sym_low = (cum_freq * scale) / context.total_freq
            sym_high = (next_cum * scale) / context.total_freq

            return symbol if value >= sym_low && value < sym_high

            cum_freq = next_cum
          end

          nil
        end
      end
    end
  end
end
