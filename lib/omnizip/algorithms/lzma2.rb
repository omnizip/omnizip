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
    # LZMA2 - Enhanced LZMA compression with chunking
    #
    # LZMA2 is an improved version of LZMA that adds:
    # - Chunked compression for better random access
    # - Support for uncompressed chunks (when compression doesn't help)
    # - Multi-threading support framework (for future enhancement)
    # - Better error recovery
    # - More compact header (single property byte)
    #
    # This implementation:
    # - Wraps LZMA encoder/decoder with chunking layer
    # - Splits data into configurable chunk sizes (default 2MB)
    # - Decides whether to compress or store each chunk uncompressed
    # - Uses control bytes to indicate chunk type and size
    #
    # The algorithm achieves similar compression ratios to LZMA
    # while providing better support for streaming and parallel processing.
    class LZMA2 < Algorithm
      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "lzma2"
          meta.description = "LZMA2 compression with chunking " \
                             "and adaptive compression"
          meta.version = "1.0.0"
        end
      end

      # Compress data using LZMA2 algorithm
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

      # Decompress LZMA2-compressed data
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

        # Dictionary size based on compression level
        if options.respond_to?(:level)
          level = options.level || 5
          opts[:dict_size] = dictionary_size_for_level(level)
          opts[:chunk_size] = chunk_size_for_level(level)
        else
          opts[:dict_size] = 1 << 23 # 8MB default
          opts[:chunk_size] = 2 * 1024 * 1024 # 2MB default
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

      # Get chunk size based on compression level
      #
      # @param level [Integer] Compression level (0-9)
      # @return [Integer] Chunk size in bytes
      def chunk_size_for_level(level)
        case level
        when 0..3 then 1 * 1024 * 1024   # 1MB for fast compression
        when 4..6 then 2 * 1024 * 1024   # 2MB for balanced
        else 4 * 1024 * 1024 # 4MB for maximum compression
        end
      end
    end
  end
end

# Load nested classes after LZMA2 class is defined
require_relative "lzma2/constants"
require_relative "lzma2/properties"
require_relative "lzma2/chunk_manager"
require_relative "lzma2/encoder"
require_relative "lzma2/decoder"

# Register the LZMA2 algorithm
Omnizip::AlgorithmRegistry.register(:lzma2, Omnizip::Algorithms::LZMA2)
