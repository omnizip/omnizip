# frozen_string_literal: true

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
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/algorithms/deflate64/constants"
      autoload :Decoder, "omnizip/algorithms/deflate64/decoder"
      autoload :Encoder, "omnizip/algorithms/deflate64/encoder"
      autoload :HuffmanCoder, "omnizip/algorithms/deflate64/huffman_coder"
      autoload :Lz77Encoder, "omnizip/algorithms/deflate64/lz77_encoder"

      # Constants
      DICTIONARY_SIZE = 65_536 # 64KB window

      # Algorithm metadata
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "deflate64"
          meta.description = "Enhanced Deflate with 64KB window"
          meta.version = "1.0.0"
        end
      end

      # Compress input stream to output stream
      #
      # @param input [IO] Input stream
      # @param output [IO] Output stream
      # @param options [Hash] Compression options
      # @option options [Integer] :level Compression level (1-9)
      def compress(input, output, options = {})
        raw_level = options[:level] || Zlib::DEFAULT_COMPRESSION
        data = input.read
        return if data.nil? || data.empty?

        # Zlib::DEFAULT_COMPRESSION (-1) maps to the FFI's 6.
        level = raw_level.negative? ? 6 : raw_level.clamp(0, 9)
        compressed = Backends.compress("zlib", data, level) do
          deflater = Zlib::Deflate.new(
            raw_level,
            Zlib::MAX_WBITS,
            Zlib::MAX_MEM_LEVEL,
          )
          result = deflater.deflate(data, Zlib::FINISH)
          deflater.close
          result
        end
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
        output.set_encoding(Encoding::BINARY)
        output.binmode

        # The streams this algorithm produces/consumes are zlib
        # containers (RFC 1950); the Rust "zlib" name speaks exactly
        # that, so the tier swap is byte-transparent.
        decompressed = Backends.decompress("zlib", compressed, Backends::UNKNOWN_LENGTH) do
          inflater = Zlib::Inflate.new(Zlib::MAX_WBITS)
          result = inflater.inflate(compressed)
          inflater.close
          result
        end

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
