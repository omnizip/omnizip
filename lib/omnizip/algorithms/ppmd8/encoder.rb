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
    class PPMd8 < PPMdBase
      # PPMd8 Encoder with enhanced features
      #
      # Encodes using PPMd8 model with restoration methods,
      # run-length encoding, and improved update algorithms.
      class Encoder
        include PPMdBase::BaseConstants
        include Constants

        attr_reader :model

        # Initialize the encoder
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :model_order Maximum context order
        # @option options [Integer] :mem_size Memory size for model
        # @option options [Integer] :restore_method Restoration method
        def initialize(output, options = {})
          @output = output
          @model = Model.new(
            options[:model_order] || DEFAULT_ORDER,
            options[:mem_size] || DEFAULT_MEM_SIZE,
            options[:restore_method] || DEFAULT_RESTORE_METHOD
          )
          @range_encoder = LZMA::RangeEncoder.new(output)
        end

        # Encode a stream of bytes
        #
        # @param input [IO] Input stream to compress
        # @return [void]
        def encode_stream(input)
          while (byte = input.getbyte)
            encode_symbol(byte)
          end

          @range_encoder.flush
        end

        private

        # Encode a single symbol
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

          encode_with_escape(symbol) if prob[:escape]

          @model.update(symbol)
        end

        # Encode with escape handling
        #
        # @param symbol [Integer] Symbol to encode
        # @return [void]
        def encode_with_escape(symbol)
          root_prob = get_root_probability(symbol)
          encode_range(
            root_prob[:cumulative_freq],
            root_prob[:freq],
            root_prob[:total_freq]
          )
        end

        # Get probability from root context
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
        # @param cum_freq [Integer] Cumulative frequency
        # @param freq [Integer] Symbol frequency
        # @param total_freq [Integer] Total frequency
        # @return [void]
        def encode_range(cum_freq, _freq, total_freq)
          scale = 0x10000
          low = (cum_freq * scale) / total_freq

          @range_encoder.encode_direct_bits(low, 16)
        end
      end
    end
  end
end
