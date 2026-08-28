# frozen_string_literal: true

require "stringio"

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
    # Pure Ruby implementation of the Zstandard format, interoperable
    # with the reference zstd CLI in both directions.
    #
    # Zstandard is particularly effective for:
    # - Real-time compression needs
    # - Network protocol compression
    # - Database compression
    # - Log file compression
    # - General-purpose compression with speed priority
    class Zstandard < Algorithm
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/algorithms/zstandard/constants"
      autoload :Encoder, "omnizip/algorithms/zstandard/encoder"
      autoload :Decoder, "omnizip/algorithms/zstandard/decoder"
      autoload :Huffman, "omnizip/algorithms/zstandard/huffman"
      autoload :HuffmanTableReader, "omnizip/algorithms/zstandard/huffman"
      autoload :HuffmanEncoder, "omnizip/algorithms/zstandard/huffman_encoder"
      autoload :LiteralsDecoder, "omnizip/algorithms/zstandard/literals"
      autoload :LiteralsEncoder, "omnizip/algorithms/zstandard/literals_encoder"
      autoload :SequencesDecoder, "omnizip/algorithms/zstandard/sequences"
      autoload :SequenceExecutor, "omnizip/algorithms/zstandard/sequences"
      autoload :SequencesEncoder,
               "omnizip/algorithms/zstandard/sequences_encoder"
      autoload :MatchFinder, "omnizip/algorithms/zstandard/match_finder"
      autoload :LdmHashTable, "omnizip/algorithms/zstandard/ldm"
      autoload :Dictionary, "omnizip/algorithms/zstandard/dictionary"
      autoload :XXHash64, "omnizip/algorithms/zstandard/xxhash"

      # Frame and FSE modules
      autoload :Frame, "omnizip/algorithms/zstandard/frame"
      autoload :FSE, "omnizip/algorithms/zstandard/fse"

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
        output_stream.set_encoding(Encoding::BINARY)
        decoder = Decoder.new(input_stream)
        decompressed = decoder.decode_stream
        output_stream.write(decompressed)
      end

      # Compress data primed with a dictionary prefix: the dictionary
      # content acts as shared history the match finder can reference,
      # dramatically improving ratios on small inputs. The resulting
      # frame carries the dictionary's ID and requires
      # decompress_with_dict to decode.
      #
      # @param input_stream [IO] plaintext
      # @param output_stream [IO] compressed frame
      # @param dict [Dictionary]
      # @param options [Hash] :level, :checksum
      # @return [void]
      def compress_with_dict(input_stream, output_stream, dict, options = {})
        encoder = Encoder.new(output_stream, build_encoder_options(options))
        encoder.encode_stream_with_dict(input_stream.read, dict)
      end

      # Decompress a frame produced by compress_with_dict. The frame's
      # dictionary ID is verified against `dict` before decoding.
      #
      # @param input_stream [IO] compressed frame
      # @param output_stream [IO] plaintext
      # @param dict [Dictionary]
      # @return [void]
      def decompress_with_dict(input_stream, output_stream, dict)
        output_stream.set_encoding(Encoding::BINARY)
        decoder = Decoder.new(input_stream)
        output_stream.write(decoder.decode_stream_with_dict(dict))
      end

      # Class-level convenience mirrors of the dictionary API.
      #
      # @return [String] compressed frame / decompressed plaintext
      def self.compress_with_dict(data, dict, **options)
        output = StringIO.new
        output.set_encoding(Encoding::BINARY)
        new(options).compress_with_dict(
          StringIO.new(data.to_s.b), output, dict, options
        )
        output.string
      end

      def self.decompress_with_dict(data, dict)
        output = StringIO.new
        output.set_encoding(Encoding::BINARY)
        new.decompress_with_dict(StringIO.new(data.to_s.b), output, dict)
        output.string
      end

      private

      # Build encoder options from compression options
      #
      # Always sets :level, defaulting to the zstd default (3) so that
      # `compress(data)` never silently degrades to stored frames
      # (issue #27). Accepts a Hash (as forwarded by Algorithm.compress)
      # or a Models::CompressionOptions.
      #
      # @param options [Models::CompressionOptions, Hash, nil]
      # @return [Hash] Encoder options
      def build_encoder_options(options)
        level = case options
                when nil then nil
                when Hash then options[:level]
                # allowed: options is a public parameter; any object with #level is honored
                else options.level if options.respond_to?(:level)
                end

        { level: map_compression_level(level) }
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

# Register the Zstandard algorithm
Omnizip::AlgorithmRegistry.register(:zstandard,
                                    Omnizip::Algorithms::Zstandard)
