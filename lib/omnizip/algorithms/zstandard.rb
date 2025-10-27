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
    # Zstandard compression algorithm
    #
    # Zstandard (or Zstd) is a fast lossless compression algorithm developed
    # by Facebook (now Meta). It provides:
    # - Excellent compression ratios comparable to zlib/deflate
    # - Very fast compression and decompression speeds
    # - Wide range of compression levels (1-22)
    # - Dictionary support for small data compression
    # - Streaming and frame modes
    #
    # This implementation uses the zstd-ruby gem which provides Ruby bindings
    # to the official Zstandard C library. This ensures compatibility with
    # the reference implementation and excellent performance.
    #
    # Zstandard is particularly effective for:
    # - Real-time compression needs
    # - Network protocol compression
    # - Database compression
    # - Log file compression
    # - General-purpose compression with speed priority
    class Zstandard < Algorithm
      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "zstandard"
          meta.description = "Zstandard fast compression with " \
                             "excellent ratios"
          meta.version = "1.0.0"
        end
      end

      # Compress data using Zstandard algorithm
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

      # Decompress Zstandard-compressed data
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

      # Map generic compression level (0-9) to Zstd level (1-22)
      #
      # @param level [Integer] Compression level (0-9)
      # @return [Integer] Zstd compression level (1-22)
      def map_compression_level(level)
        return 3 if level.nil? # Zstd default

        case level
        when 0 then 1      # Fastest
        when 1 then 2
        when 2 then 3
        when 3 then 5
        when 4 then 7
        when 5 then 10
        when 6 then 13
        when 7 then 16
        when 8 then 19
        when 9 then 22     # Maximum
        else level
        end
      end
    end
  end
end

# Load nested classes after Zstandard class is defined
require_relative "zstandard/constants"
require_relative "zstandard/encoder"
require_relative "zstandard/decoder"

# Register the Zstandard algorithm
Omnizip::AlgorithmRegistry.register(:zstandard,
                                    Omnizip::Algorithms::Zstandard)
