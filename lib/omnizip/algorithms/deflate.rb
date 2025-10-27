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
    # Deflate compression algorithm (RFC 1951)
    #
    # Deflate is a widely-used lossless data compression algorithm that
    # combines LZ77 compression with Huffman coding. It is the foundation
    # of many popular formats including ZIP, gzip, and PNG.
    #
    # The algorithm works in two phases:
    # 1. LZ77 compression - Identifies repeated byte sequences
    # 2. Huffman coding - Encodes the result using variable-length codes
    #
    # This implementation uses Ruby's Zlib library which provides a
    # well-tested, efficient implementation of the Deflate algorithm.
    #
    # Deflate is particularly effective for:
    # - Text files and source code
    # - HTML, XML, and JSON documents
    # - Files with repeated patterns
    # - General-purpose compression needs
    class Deflate < Algorithm
      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "deflate"
          meta.description = "Deflate compression using LZ77 and " \
                             "Huffman coding (RFC 1951)"
          meta.version = "1.0.0"
        end
      end

      # Compress data using Deflate algorithm
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

      # Decompress Deflate-compressed data
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
          opts[:level] = map_compression_level(options.level)
        end

        opts
      end

      # Map generic compression level (0-9) to Zlib level
      #
      # @param level [Integer] Compression level (0-9)
      # @return [Integer] Zlib compression level
      def map_compression_level(level)
        return Zlib::DEFAULT_COMPRESSION if level.nil?

        case level
        when 0 then Zlib::NO_COMPRESSION
        when 1 then Zlib::BEST_SPEED
        when 9 then Zlib::BEST_COMPRESSION
        else level
        end
      end
    end
  end
end

# Load nested classes after Deflate class is defined
require_relative "deflate/constants"
require_relative "deflate/encoder"
require_relative "deflate/decoder"

# Register the Deflate algorithm
Omnizip::AlgorithmRegistry.register(:deflate, Omnizip::Algorithms::Deflate)
