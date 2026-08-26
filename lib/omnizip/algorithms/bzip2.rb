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
      # Nested classes - autoloaded
      autoload :Bwt, "omnizip/algorithms/bzip2/bwt"
      autoload :Rle, "omnizip/algorithms/bzip2/rle"
      autoload :Bz2, "omnizip/algorithms/bzip2/bz2"

      # Cross-namespace dependencies - autoloaded
      autoload :Crc32, "omnizip/checksums/crc32"

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
        level = level_from(options)
        output_stream.write(Bz2.compress(input_stream.read, level))
      end

      # Decompress BZip2-compressed data
      #
      # @param input_stream [IO] Input stream of compressed data
      # @param output_stream [IO] Output stream for decompressed data
      # @param options [Models::CompressionOptions] Decompression options
      # @return [void]
      def decompress(input_stream, output_stream, _options = nil)
        output_stream.set_encoding(Encoding::BINARY)
        output_stream.write(Bz2.decompress(input_stream.read))
      end

      private

      # Compression level (1-9) from options; bzip2's levels map
      # directly to 100 KB..900 KB block sizes.
      def level_from(options)
        return 9 if options.nil?
        return (options[:level] || 9).clamp(1, 9) if options.is_a?(Hash)

        # allowed: options is a public parameter; any object with #level is honored
        level = options.respond_to?(:level) ? options.level : nil
        (level || 9).clamp(1, 9)
      end
    end
  end
end

# Register the BZip2 algorithm
Omnizip::AlgorithmRegistry.register(:bzip2, Omnizip::Algorithms::BZip2)
