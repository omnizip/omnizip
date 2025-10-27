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

require_relative "../algorithm"
require_relative "../models/algorithm_metadata"

module Omnizip
  module Algorithms
    # LZMA (Lempel-Ziv-Markov chain Algorithm) compression
    #
    # LZMA is a lossless data compression algorithm that combines
    # Lempel-Ziv dictionary compression with range coding (a form
    # of arithmetic coding). It achieves high compression ratios
    # by using adaptive probability models.
    #
    # This implementation uses:
    # - LZ77 match finder for finding duplicate sequences
    # - Range coding for probability-based encoding
    # - Adaptive bit models that adjust based on input data
    # - State machine for compression context tracking
    #
    # The algorithm operates by:
    # 1. Finding matches using LZ77 dictionary compression
    # 2. Encoding decisions using range coder with probability models
    # 3. Maintaining state for optimal compression
    class LZMA < Algorithm
      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "lzma"
          meta.description = "LZMA compression using range coding " \
                             "and dictionary compression"
          meta.version = "1.0.0"
        end
      end

      # Compress data using LZMA algorithm
      #
      # @param input_stream [IO] Input stream to compress
      # @param output_stream [IO] Output stream for compressed data
      # @param options [Models::CompressionOptions] Compression options
      # @return [void]
      def compress(input_stream, output_stream, options = nil)
        input_data = input_stream.read
        encoder = Encoder.new(output_stream, build_encoder_options(options))
        encoder.encode_stream(input_data)
      end

      # Decompress LZMA-compressed data
      #
      # @param input_stream [IO] Input stream of compressed data
      # @param output_stream [IO] Output stream for decompressed data
      # @param options [Models::CompressionOptions] Decompression options
      # @return [void]
      def decompress(input_stream, output_stream, _options = nil)
        decoder = Decoder.new(input_stream)
        decompressed = decoder.decode_stream
        output_stream.write(decompressed)
      end

      private

      # Build encoder options from compression options
      #
      # @param options [Models::CompressionOptions, nil] Compression opts
      # @return [Hash] Encoder options
      def build_encoder_options(options)
        return {} if options.nil?

        opts = {}
        opts[:lc] = 3
        opts[:lp] = 0
        opts[:pb] = 2
        opts[:dict_size] = 1 << 23

        if options.respond_to?(:level)
          level = options.level || 5
          opts[:dict_size] = dictionary_size_for_level(level)
        end

        opts
      end

      # Get dictionary size based on compression level
      #
      # @param level [Integer] Compression level (0-9)
      # @return [Integer] Dictionary size in bytes
      def dictionary_size_for_level(level)
        1 << case level
             when 0..1 then 16   # 64KB
             when 2..3 then 20   # 1MB
             when 4..5 then 22   # 4MB
             when 6..7 then 23   # 8MB
             else 24 # 16MB
             end
      end
    end
  end
end

# Load nested classes after LZMA class is defined
require_relative "lzma/constants"
require_relative "lzma/bit_model"
require_relative "lzma/range_coder"
require_relative "lzma/range_encoder"
require_relative "lzma/range_decoder"
require_relative "lzma/match_finder"
require_relative "lzma/state"
require_relative "lzma/encoder"
require_relative "lzma/decoder"

# Register the LZMA algorithm
Omnizip::AlgorithmRegistry.register(:lzma, Omnizip::Algorithms::LZMA)
