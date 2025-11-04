# frozen_string_literal: true

require_relative "../algorithm"
require_relative "deflate64/constants"
require_relative "deflate64/encoder"
require_relative "deflate64/decoder"

module Omnizip
  module Algorithms
    # Deflate64 (Enhanced Deflate) compression algorithm
    #
    # Extends standard Deflate with:
    # - 64KB sliding window (vs 32KB)
    # - Better compression for large files
    # - ZIP compression method 9
    class Deflate64 < Algorithm
      include Deflate64::Constants

      # Algorithm metadata
      def self.metadata
        {
          name: "Deflate64",
          type: :compression,
          streaming_supported: true,
          dictionary_size: DICTIONARY_SIZE,
          compression_method: 9,
          description: "Enhanced Deflate with 64KB window"
        }
      end

      # Compress input stream to output stream
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @param options [Hash] Compression options
      # @option options [Integer] :level Compression level (1-9)
      def compress(input, output, options = {})
        encoder = Deflate64::Encoder.new(output, options)
        encoder.compress(input)
      end

      # Decompress input stream to output stream
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @param options [Hash] Decompression options
      def decompress(input, output, options = {})
        decoder = Deflate64::Decoder.new(input)
        decoder.decompress(output)
      end

      # Check if streaming is supported
      #
      # @return [Boolean] Always true for Deflate64
      def self.streaming_supported?
        true
      end

      # Get dictionary size
      #
      # @return [Integer] 64KB
      def self.dictionary_size
        DICTIONARY_SIZE
      end

      # Get compression method ID for ZIP format
      #
      # @return [Integer] Method 9
      def self.compression_method
        9
      end
    end
  end
end

# Register algorithm
Omnizip::AlgorithmRegistry.register(:deflate64, Omnizip::Algorithms::Deflate64)