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

require "stringio"

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
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/algorithms/ppmd7/constants"
      autoload :SymbolState, "omnizip/algorithms/ppmd7/symbol_state"
      autoload :Context, "omnizip/algorithms/ppmd7/context"
      autoload :Model, "omnizip/algorithms/ppmd7/model"
      autoload :Encoder, "omnizip/algorithms/ppmd7/encoder"
      autoload :Decoder, "omnizip/algorithms/ppmd7/decoder"

      # Cross-namespace dependencies - autoloaded
      autoload :RangeDecoder, "omnizip/algorithms/lzma/range_decoder"
      autoload :RangeEncoder, "omnizip/algorithms/lzma/range_encoder"

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
        data = input.read
        order = options[:model_order] || PPMd7::Model::DEFAULT_ORDER
        mem = options[:mem_size] || PPMd7::Model::DEFAULT_MEM_SIZE

        # The tier is the authority: Rust's PPMd (the reference-grade
        # port) frames order/size in-band; params travel in the codec
        # name. The pure-Ruby core cannot round-trip its own output
        # beyond ~100 bytes (its decoder reads root-only) — it stays
        # only as the no-dylib fallback.
        output.write(
          Backends.compress("ppmd7:o#{order}:m#{mem}", data, order) do
            encoder = PPMd7::Encoder.new(output, options)
            encoder.encode_stream(StringIO.new(data))
            nil
          end,
        )
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
        compressed = input.read
        order = options[:model_order] || PPMd7::Model::DEFAULT_ORDER
        mem = options[:mem_size] || PPMd7::Model::DEFAULT_MEM_SIZE

        result = Backends.decompress(
          "ppmd7:o#{order}:m#{mem}", compressed, Backends::UNKNOWN_LENGTH
        ) do
          decoder = PPMd7::Decoder.new(StringIO.new(compressed), options)
          decoder.decode_stream
        end
        output.write(result)
      end

      private

      # Prepare input for processing
      #
      # @param input [IO, String] Input data
      # @return [IO] IO object ready for reading
      def prepare_input(input)
        # StringIO is not an ::IO, and its #to_s is Kernel's (the
        # INSPECT string) — pass anything readable straight through.
        return input if input.respond_to?(:read) # allowed: IO-duck detection — StringIO must pass through (its #to_s is the INSPECT string)

        StringIO.new(input.to_s)
      end

      # Prepare output for processing
      #
      # @param output [IO, String, nil] Output destination
      # @return [IO] IO object ready for writing
      def prepare_output(output)
        # StringIO is NOT an ::IO subclass — the old check discarded
        # it for a fresh buffer, silently dropping every class-level
        # compress's output.
        return output if output.is_a?(IO) || output.is_a?(StringIO)

        StringIO.new(String.new(encoding: Encoding::BINARY))
      end
    end
  end
end

# Register algorithm with registry
Omnizip::AlgorithmRegistry.register(:ppmd7, Omnizip::Algorithms::PPMd7)
