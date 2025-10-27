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
    # BZip2 block-sorting compression algorithm
    #
    # BZip2 combines several compression techniques in a pipeline:
    # 1. Burrows-Wheeler Transform (BWT) - block-sorting transformation
    # 2. Move-to-Front Transform (MTF) - exploits locality
    # 3. Run-Length Encoding (RLE) - compresses repeated bytes
    # 4. Huffman Coding - variable-length entropy encoding
    #
    # This algorithm is particularly effective for:
    # - Text files with repetitive patterns
    # - Data with high local similarity
    # - Files where block-sorting improves compressibility
    #
    # Block size affects both compression ratio and memory usage.
    # Larger blocks (up to 900KB) generally provide better compression
    # but require more memory.
    class BZip2 < Algorithm
      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "bzip2"
          meta.description = "BZip2 block-sorting compression using " \
                             "BWT, MTF, RLE, and Huffman coding"
          meta.version = "1.0.0"
        end
      end

      # Compress data using BZip2 algorithm
      #
      # @param input_stream [IO] Input stream to compress
      # @param output_stream [IO] Output stream for compressed data
      # @param options [Models::CompressionOptions] Compression options
      # @return [void]
      def compress(input_stream, output_stream, options = nil)
        input_data = input_stream.read
        encoder = Encoder.new(output_stream,
                              build_encoder_options(options))
        encoder.encode_stream(input_data)
      end

      # Decompress BZip2-compressed data
      #
      # @param input_stream [IO] Input stream of compressed data
      # @param output_stream [IO] Output stream for decompressed data
      # @param options [Models::CompressionOptions] Decompression options
      # @return [void]
      def decompress(input_stream, output_stream, _options = nil)
        if output_stream.respond_to?(:set_encoding)
          output_stream.set_encoding(Encoding::BINARY)
        end
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

        if options.respond_to?(:level)
          level = options.level || 9
          opts[:block_size] = block_size_for_level(level)
        end

        opts
      end

      # Get block size based on compression level
      #
      # BZip2 traditionally uses levels 1-9 corresponding to
      # 100KB-900KB block sizes
      #
      # @param level [Integer] Compression level (1-9)
      # @return [Integer] Block size in bytes
      def block_size_for_level(level)
        # Clamp level to valid range
        level = [[level, 1].max, 9].min
        # Each level = 100KB
        level * 100_000
      end
    end
  end
end

# Load nested classes after BZip2 class is defined
require_relative "bzip2/bwt"
require_relative "bzip2/mtf"
require_relative "bzip2/rle"
require_relative "bzip2/huffman"
require_relative "bzip2/encoder"
require_relative "bzip2/decoder"

# Register the BZip2 algorithm
Omnizip::AlgorithmRegistry.register(:bzip2, Omnizip::Algorithms::BZip2)
