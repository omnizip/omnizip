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
    # LZMA (Lempel-Ziv-Markov chain Algorithm) compression
    #
    # LZMA is a lossless data compression algorithm that combines
    # Lempel-Ziv dictionary compression with range coding (a form
    # of arithmetic coding). It achieves high compression ratios
    # by using adaptive probability models.
    #
    # This implementation uses:
    # - LZ77 match finder for finding duplicate sequences
    # - Range coding for probability-based encoding
    # - Adaptive bit models that adjust based on input data
    # - State machine for compression context tracking
    #
    # The algorithm operates by:
    # 1. Finding matches using LZ77 dictionary compression
    # 2. Encoding decisions using range coder with probability models
    # 3. Maintaining state for optimal compression
    class LZMA < Algorithm
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/algorithms/lzma/constants"
      autoload :BitModel, "omnizip/algorithms/lzma/bit_model"
      autoload :ProbabilityModels, "omnizip/algorithms/lzma/probability_models"
      autoload :XZRangeEncoder, "omnizip/algorithms/lzma/xz_range_encoder"
      autoload :Dictionary, "omnizip/algorithms/lzma/dictionary"
      autoload :LZMAState, "omnizip/algorithms/lzma/lzma_state"
      autoload :RangeCoder, "omnizip/algorithms/lzma/range_coder"
      autoload :RangeEncoder, "omnizip/algorithms/lzma/range_encoder"
      autoload :RangeDecoder, "omnizip/algorithms/lzma/range_decoder"
      autoload :Match, "omnizip/algorithms/lzma/match"
      autoload :MatchFinder, "omnizip/algorithms/lzma/match_finder"
      autoload :OptimalEncoder, "omnizip/algorithms/lzma/optimal_encoder"
      autoload :State, "omnizip/algorithms/lzma/state"
      autoload :XzState, "omnizip/algorithms/lzma/xz_state"
      autoload :XzProbabilityModels,
               "omnizip/algorithms/lzma/xz_probability_models"
      autoload :XzPriceCalculator, "omnizip/algorithms/lzma/xz_price_calculator"
      autoload :XzMatchFinderAdapter,
               "omnizip/algorithms/lzma/xz_match_finder_adapter"
      autoload :LengthCoder, "omnizip/algorithms/lzma/length_coder"
      autoload :DistanceCoder, "omnizip/algorithms/lzma/distance_coder"
      autoload :LiteralEncoder, "omnizip/algorithms/lzma/literal_encoder"
      autoload :LiteralDecoder, "omnizip/algorithms/lzma/literal_decoder"
      autoload :MatchFinderConfig, "omnizip/algorithms/lzma/match_finder_config"
      autoload :MatchFinderFactory,
               "omnizip/algorithms/lzma/match_finder_factory"
      autoload :XzEncoder, "omnizip/algorithms/lzma/xz_encoder"
      autoload :XzEncoderFast, "omnizip/algorithms/lzma/xz_encoder_fast"
      autoload :XzBufferedRangeEncoder,
               "omnizip/algorithms/lzma/xz_buffered_range_encoder"
      autoload :XzRangeEncoderExact,
               "omnizip/algorithms/lzma/xz_range_encoder_exact"
      autoload :XzRangeEncoder, "omnizip/algorithms/lzma/xz_range_encoder_exact"
      autoload :Encoder, "omnizip/algorithms/lzma/encoder"
      autoload :Decoder, "omnizip/algorithms/lzma/decoder"
      autoload :LzmaAloneDecoder, "omnizip/algorithms/lzma/lzma_alone_decoder"
      autoload :LzipDecoder, "omnizip/algorithms/lzma/lzip_decoder"

      # Cross-namespace dependencies - autoloaded
      autoload :Crc32, "omnizip/checksums/crc32"
      autoload :SevenZipLzmaEncoder,
               "omnizip/implementations/seven_zip/lzma/encoder"
      autoload :SevenZipMatchFinder,
               "omnizip/implementations/seven_zip/lzma/match_finder"

      # Initialize the LZMA algorithm with options
      #
      # @param options [Hash] Algorithm options
      # @option options [Integer] :lc Literal context bits (default: 3)
      # @option options [Integer] :lp Literal position bits (default: 0)
      # @option options [Integer] :pb Position bits (default: 2)
      # @option options [Integer] :dict_size Dictionary size (default: 4MB)
      # @option options [Boolean] :lzma2_mode Raw LZMA mode (no header, for 7-Zip)
      def initialize(options = {})
        super()
        @lc = options[:lc] || 3
        @lp = options[:lp] || 0
        @pb = options[:pb] || 2
        @dict_size = options[:dict_size] || (4 * 1024 * 1024) # 4 MB default
        @lzma2_mode = options[:lzma2_mode]
        @uncompressed_size = options[:uncompressed_size] || options[:size]
      end

      # Get algorithm metadata
      #
      # @return [AlgorithmMetadata] Algorithm information
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |meta|
          meta.name = "lzma"
          meta.description = "LZMA compression using range coding " \
                             "and dictionary compression"
          meta.version = "1.0.0"
        end
      end

      # Compress data using LZMA algorithm
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

      # Decompress LZMA-compressed data
      #
      # @param input_stream [IO] Input stream of compressed data
      # @param output_stream [IO] Output stream for decompressed data
      # @param options [Models::CompressionOptions, Hash] Decompression options
      # @return [IO] The output_stream (for chaining)
      def decompress(input_stream, output_stream, options = nil)
        # Set binary encoding on output stream for proper byte handling
        output_stream.set_encoding(Encoding::BINARY) if output_stream.respond_to?(:set_encoding)

        # Build decoder options, merging with instance variables as fallbacks
        decoder_opts = build_decoder_options(options)
        if @lzma2_mode && !decoder_opts.key?(:lzma2_mode)
          decoder_opts[:lzma2_mode] =
            @lzma2_mode
        end
        decoder_opts[:lc] = @lc if @lc && !decoder_opts.key?(:lc)
        decoder_opts[:lp] = @lp if @lp && !decoder_opts.key?(:lp)
        decoder_opts[:pb] = @pb if @pb && !decoder_opts.key?(:pb)
        if @dict_size && !decoder_opts.key?(:dict_size)
          decoder_opts[:dict_size] =
            @dict_size
        end
        if @uncompressed_size && !decoder_opts.key?(:uncompressed_size)
          decoder_opts[:uncompressed_size] =
            @uncompressed_size
        end
        decoder_opts[:uncompressed_size] ||= options[:size] if options.respond_to?(:key?) && options.key?(:size)

        decoder = Decoder.new(input_stream, decoder_opts)
        decoder.decode_stream(output_stream)
        output_stream
      end

      private

      # Build encoder options from compression options
      #
      # @param options [Models::CompressionOptions, Hash, nil] Compression opts
      # @return [Hash] Encoder options
      def build_encoder_options(options)
        return {} if options.nil?

        opts = {}

        # Handle Hash-like options
        if options.respond_to?(:[])
          opts[:lc] = options[:lc] if options[:lc]
          opts[:lp] = options[:lp] if options[:lp]
          opts[:pb] = options[:pb] if options[:pb]
          opts[:dict_size] = options[:dict_size] if options[:dict_size]
          opts[:write_size] = options[:write_size] if options.key?(:write_size)
          if options.key?(:sdk_compatible)
            opts[:sdk_compatible] =
              options[:sdk_compatible]
          end
          if options.key?(:xz_compatible)
            opts[:xz_compatible] =
              options[:xz_compatible]
          end
          opts[:raw_mode] = options[:raw_mode] if options.key?(:raw_mode)
        end

        # Handle level from both Hash and CompressionOptions
        level = if options.respond_to?(:level)
                  options.level || 5
                elsif options.respond_to?(:[]) && options[:level]
                  options[:level] || 5
                else
                  5
                end

        opts[:dict_size] ||= dictionary_size_for_level(level)

        opts
      end

      # Build decoder options from decompression options
      #
      # @param options [Models::CompressionOptions, Hash, nil] Decompression opts
      # @return [Hash] Decoder options
      def build_decoder_options(options)
        return {} if options.nil?

        # Handle case where options is an Integer (uncompressed size) instead of Hash
        return {} if options.is_a?(Integer)

        opts = {}

        # Handle Hash-like options - pass through all decoder-relevant options
        if options.respond_to?(:key?)
          if options.key?(:sdk_compatible)
            opts[:sdk_compatible] =
              options[:sdk_compatible]
          end
          opts[:lzma2_mode] = options[:lzma2_mode] if options.key?(:lzma2_mode)
          opts[:lc] = options[:lc] if options.key?(:lc)
          opts[:lp] = options[:lp] if options.key?(:lp)
          opts[:pb] = options[:pb] if options.key?(:pb)
          opts[:dict_size] = options[:dict_size] if options.key?(:dict_size)
          if options.key?(:uncompressed_size)
            opts[:uncompressed_size] =
              options[:uncompressed_size]
          end
          opts[:size] = options[:size] if options.key?(:size)
        end

        opts
      end

      # Get dictionary size based on compression level
      #
      # @param level [Integer] Compression level (0-9)
      # @return [Integer] Dictionary size in bytes
      def dictionary_size_for_level(level)
        1 << case level
             when 0..1 then 16   # 64KB
             when 2..3 then 20   # 1MB
             when 4..5 then 22   # 4MB
             when 6..7 then 23   # 8MB
             else 24 # 16MB
             end
      end
    end
  end
end

# Register the LZMA algorithm
Omnizip::AlgorithmRegistry.register(:lzma, Omnizip::Algorithms::LZMA)
