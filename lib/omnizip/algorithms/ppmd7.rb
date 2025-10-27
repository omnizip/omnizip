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
require_relative "ppmd7/constants"
require_relative "ppmd7/symbol_state"
require_relative "ppmd7/context"
require_relative "ppmd7/model"
require_relative "ppmd7/encoder"
require_relative "ppmd7/decoder"

module Omnizip
  module Algorithms
    # PPMd7 compression algorithm
    #
    # PPMd (Prediction by Partial Matching) is a statistical compression
    # algorithm that excels at text compression. It uses context-based
    # prediction to achieve high compression ratios on text files.
    #
    # This implementation follows the PPMd7 specification as used in 7-Zip.
    class PPMd7 < Algorithm
      include Constants

      # Algorithm metadata
      #
      # @return [AlgorithmMetadata] Metadata describing this algorithm
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |m|
          m.name = "ppmd7"
          m.description = "PPMd7 - Prediction by Partial Matching " \
                          "for statistical text compression"
          m.version = "1.0.0"
          m.supports_streaming = true
        end
      end

      # Compress data using PPMd7
      #
      # @param input [IO, String] Input data to compress
      # @param output [IO, String] Output for compressed data
      # @param options [Hash] Compression options
      # @option options [Integer] :model_order Context order (2-16)
      # @option options [Integer] :mem_size Memory size
      # @return [void]
      def compress(input, output, options = {})
        input = prepare_input(input)
        output = prepare_output(output)

        encoder = PPMd7::Encoder.new(output, options)
        encoder.encode_stream(input)
      end

      # Decompress data using PPMd7
      #
      # @param input [IO, String] Compressed input data
      # @param output [IO, String] Output for decompressed data
      # @param options [Hash] Decompression options
      # @option options [Integer] :model_order Context order (2-16)
      # @option options [Integer] :mem_size Memory size
      # @return [void]
      def decompress(input, output, options = {})
        input = prepare_input(input)
        output = prepare_output(output)

        decoder = PPMd7::Decoder.new(input, options)
        result = decoder.decode_stream

        output.write(result)
      end

      private

      # Prepare input for processing
      #
      # @param input [IO, String] Input data
      # @return [IO] IO object ready for reading
      def prepare_input(input)
        return input if input.is_a?(IO)

        StringIO.new(input.to_s)
      end

      # Prepare output for processing
      #
      # @param output [IO, String, nil] Output destination
      # @return [IO] IO object ready for writing
      def prepare_output(output)
        return output if output.is_a?(IO)

        StringIO.new(String.new(encoding: Encoding::BINARY))
      end
    end
  end
end

# Register algorithm with registry
Omnizip::AlgorithmRegistry.register(:ppmd7, Omnizip::Algorithms::PPMd7)
