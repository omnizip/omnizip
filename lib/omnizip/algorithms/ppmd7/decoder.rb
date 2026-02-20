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
        # original symbol value using proper range decoding.
        #
        # @return [Integer, nil] Decoded byte or nil if end
        def decode_symbol
          # Get context for decoding
          context = @model.root_context
          total_freq = context.total_freq

          return nil if total_freq.zero?

          # Decode cumulative frequency using proper range decoding
          cum_freq_value = @range_decoder.decode_freq(total_freq)

          # Find symbol from cumulative frequency value
          symbol, cum_freq, freq = find_symbol_from_cum_freq(context, cum_freq_value)
          return nil if symbol.nil?

          # Normalize the range decoder state
          @range_decoder.normalize_freq(cum_freq, freq, total_freq)

          # Update model to stay in sync with encoder
          @model.update(symbol)

          symbol
        end

        # Find symbol from cumulative frequency value
        #
        # Maps the decoded cumulative frequency back to a symbol
        # using the context's probability distribution.
        #
        # @param context [Context] The current context
        # @param cum_freq_value [Integer] Decoded cumulative frequency
        # @return [Array<Integer, Integer, Integer>] symbol, cum_freq, freq
        def find_symbol_from_cum_freq(context, cum_freq_value)
          cum_freq = 0

          context.states.keys.sort.each do |symbol|
            state = context.states[symbol]
            freq = state.freq
            next_cum = cum_freq + freq

            return [symbol, cum_freq, freq] if cum_freq_value < next_cum

            cum_freq = next_cum
          end

          nil
        end
      end
    end
  end
end
