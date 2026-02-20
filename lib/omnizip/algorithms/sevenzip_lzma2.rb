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
require_relative "../algorithms/lzma2/encoder"
require_relative "../algorithms/lzma2/decoder"

module Omnizip
  module Algorithms
    # 7-Zip LZMA2 compression algorithm.
    #
    # This algorithm uses the 7-Zip SDK-compatible implementation of LZMA2,
    # which provides compatibility with 7-Zip command-line tools.
    #
    # @example Compress data
    #   algorithm = Omnizip::AlgorithmRegistry.get(:sevenzip_lzma2).new(
    #     dict_size: 8 * 1024 * 1024
    #   )
    #   algorithm.compress(input_io, output_io)
    #
    # @example Decompress data
    #   algorithm = Omnizip::AlgorithmRegistry.get(:sevenzip_lzma2).new
    #   algorithm.decompress(input_io, output_io)
    class SevenZipLZMA2 < Algorithm
      # Get algorithm metadata.
      #
      # @return [Models::AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "sevenzip_lzma2"
          meta.description = "LZMA2 compression (7-Zip SDK implementation)"
          meta.version = "1.0.0"
        end
      end

      # Compress data using 7-Zip LZMA2.
      #
      # @param input [IO, String] Input data
      # @param output [IO] Output stream
      # @return [void]
      def compress(input, output)
        # Apply filter if set
        input_data = if input.is_a?(String)
                       if @filter
                         @filter.encode(input)
                       else
                         input
                       end
                     elsif input.respond_to?(:read)
                       data = input.read
                       if @filter
                         @filter.encode(data)
                       else
                         data
                       end
                     else
                       raise ArgumentError, "Input must be a String or IO"
                     end

        # Get encoding options
        dict_size = @options.fetch(:dict_size, 8 * 1024 * 1024)
        lc = @options.fetch(:lc, 3)
        lp = @options.fetch(:lp, 0)
        pb = @options.fetch(:pb, 2)

        # Use existing LZMA2Encoder which wraps SimpleLZMA2Encoder
        encoder = LZMA2::LZMA2Encoder.new(
          dict_size: dict_size,
          lc: lc,
          lp: lp,
          pb: pb,
          standalone: false,
        )

        compressed = encoder.encode(input_data)
        output.write(compressed)
      end

      # Decompress data using 7-Zip LZMA2.
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @return [void]
      def decompress(input, output)
        dict_size = @options.fetch(:dict_size, 8 * 1024 * 1024)

        # Use existing LZMA2::Decoder
        decoder = LZMA2::Decoder.new(input, raw_mode: true,
                                            dict_size: dict_size)
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
Omnizip::Algorithms::SevenZipLZMA2.register_algorithm
