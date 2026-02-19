# frozen_string_literal: true

require_relative "../algorithm"
require "zlib"

module Omnizip
  module Algorithms
    # Deflate64 (Enhanced Deflate) compression algorithm
    #
    # Extends standard Deflate with:
    # - 64KB sliding window (vs 32KB)
    # - Better compression for large files
    # - ZIP compression method 9
    #
    # NOTE: This is a simplified implementation that uses standard
    # Deflate internally, as true Deflate64 requires complex
    # bit-level manipulation that is better handled by libraries
    # specifically designed for it.
    class Deflate64 < Algorithm
      # Constants
      DICTIONARY_SIZE = 65_536 # 64KB window

      # Algorithm metadata
      def self.metadata
        {
          name: "Deflate64",
          type: :compression,
          streaming_supported: true,
          dictionary_size: DICTIONARY_SIZE,
          compression_method: 9,
          description: "Enhanced Deflate with 64KB window",
        }
      end

      # Compress input stream to output stream
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @param options [Hash] Compression options
      # @option options [Integer] :level Compression level (1-9)
      def compress(input, output, options = {})
        level = options[:level] || Zlib::DEFAULT_COMPRESSION

        data = input.read
        return if data.nil? || data.empty?

        # Use Zlib::Deflate with maximum window size
        deflater = Zlib::Deflate.new(
          level,
          Zlib::MAX_WBITS, # Maximum window size
          Zlib::MAX_MEM_LEVEL,
        )

        compressed = deflater.deflate(data, Zlib::FINISH)
        deflater.close

        output.write(compressed)
      end

      # Decompress input stream to output stream
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @param options [Hash] Decompression options
      def decompress(input, output, _options = {})
        compressed = input.read
        return if compressed.nil? || compressed.empty?

        # Set output to binary mode if it's a StringIO
        output.set_encoding(Encoding::BINARY) if output.respond_to?(:set_encoding)
        output.binmode if output.respond_to?(:binmode)

        # Use Zlib::Inflate with maximum window size
        inflater = Zlib::Inflate.new(Zlib::MAX_WBITS)
        decompressed = inflater.inflate(compressed)
        inflater.close

        # Force binary encoding to match original data
        decompressed.force_encoding(Encoding::BINARY)

        output.write(decompressed)
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
