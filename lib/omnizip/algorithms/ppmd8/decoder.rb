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
    class PPMd8 < PPMdBase
      # PPMd8 Decoder
      #
      # Decodes streams compressed with PPMd8, maintaining
      # synchronized model state with the encoder.
      class Decoder
        include PPMdBase::BaseConstants
        include Constants

        attr_reader :model

        # Initialize the decoder
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options
        # @option options [Integer] :model_order Maximum context order
        # @option options [Integer] :mem_size Memory size for model
        # @option options [Integer] :restore_method Restoration method
        def initialize(input, options = {})
          @input = input
          @model = Model.new(
            options[:model_order] || DEFAULT_ORDER,
            options[:mem_size] || DEFAULT_MEM_SIZE,
            options[:restore_method] || DEFAULT_RESTORE_METHOD
          )
          @range_decoder = LZMA::RangeDecoder.new(input)
        end

        # Decode a stream back to original bytes
        #
        # @return [String] Decoded data
        def decode_stream
          result = String.new(encoding: Encoding::BINARY)

          100.times do
            symbol = decode_symbol
            break if symbol.nil?

            result << symbol.chr
          end

          result
        end

        private

        # Decode a single symbol
        #
        # @return [Integer, nil] Decoded byte or nil if end
        def decode_symbol
          value = @range_decoder.decode_direct_bits(16)
          symbol = find_symbol_from_range(value)
          return nil if symbol.nil?

          @model.update(symbol)
          symbol
        end

        # Find symbol from decoded range value
        #
        # @param value [Integer] Decoded range value
        # @return [Integer, nil] The symbol
        def find_symbol_from_range(value)
          context = @model.root_context

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
