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
require_relative "../implementations/xz_utils/lzma2/encoder"
require_relative "../implementations/xz_utils/lzma2/decoder"

module Omnizip
  module Algorithms
    # XZ Utils LZMA2 compression algorithm.
    #
    # This algorithm uses the XZ Utils implementation of LZMA2,
    # which provides full compatibility with xz command-line tools.
    #
    # @example Compress data
    #   algorithm = Omnizip::AlgorithmRegistry.get(:xz_lzma2).new(
    #     dict_size: 8 * 1024 * 1024
    #   )
    #   algorithm.compress(input_io, output_io)
    #
    # @example Decompress data
    #   algorithm = Omnizip::AlgorithmRegistry.get(:xz_lzma2).new
    #   algorithm.decompress(input_io, output_io)
    class XZLZMA2 < Algorithm
      # Get algorithm metadata.
      #
      # @return [Models::AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "xz_lzma2"
          meta.description = "LZMA2 compression (XZ Utils implementation)"
          meta.version = "1.0.0"
        end
      end

      # Compress data using XZ Utils LZMA2.
      #
      # @param input [IO, String] Input data
      # @param output [IO] Output stream
      # @return [void]
      def compress(input, output)
        input_data = if input.is_a?(String)
                       input
                     elsif input.respond_to?(:read)
                       input.read
                     else
                       raise ArgumentError, "Input must be a String or IO"
                     end

        # Apply filter if set
        if @filter
          input_data = @filter.encode(input_data)
        end

        # Get encoding options
        dict_size = @options.fetch(:dict_size, 8 * 1024 * 1024)
        lc = @options.fetch(:lc, 3)
        lp = @options.fetch(:lp, 0)
        pb = @options.fetch(:pb, 2)
        standalone = @options.fetch(:standalone, false)

        # Create encoder and compress
        encoder = Implementations::XZUtils::LZMA2::Encoder.new(
          dict_size: dict_size,
          lc: lc,
          lp: lp,
          pb: pb,
          standalone: standalone,
        )

        compressed = encoder.encode(input_data)
        output.write(compressed)
      end

      # Decompress data using XZ Utils LZMA2.
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @return [void]
      def decompress(input, output)
        dict_size = @options.fetch(:dict_size, 8 * 1024 * 1024)

        decoder = Implementations::XZUtils::LZMA2::Decoder.new(input,
                                                               raw_mode: true, dict_size: dict_size)
        decompressed = decoder.decode_stream

        # Reverse filter if set
        if @filter
          decompressed = @filter.decode(decompressed)
        end

        output.write(decompressed)
      end
    end
  end
end

# Register the algorithm
Omnizip::Algorithms::XZLZMA2.register_algorithm
