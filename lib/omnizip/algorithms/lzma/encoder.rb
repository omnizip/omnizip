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

require_relative "constants"
require_relative "xz_encoder"
require_relative "../../implementations/seven_zip/lzma/encoder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZMA Encoder - Factory for LZMA compression implementations
      #
      # This class provides a unified interface for LZMA encoding, delegating
      # to the appropriate implementation based on the target format:
      #
      # 1. SDK-compatible (default): For 7-Zip containers, uses 7-Zip SDK implementation
      # 2. XZ-compatible: For XZ/LZMA files, uses XZ Utils implementation
      #
      # The encoder produces a stream that consists of:
      # - Property byte (lc, lp, pb parameters)
      # - Dictionary size (4 bytes)
      # - Uncompressed size (8 bytes)
      # - Compressed data
      class Encoder
        include Constants

        attr_reader :dict_size, :lc, :lp, :pb

        # Initialize the encoder
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :dict_size Dictionary size
        # @option options [Integer] :lc Literal context bits (0-8)
        # @option options [Integer] :lp Literal position bits (0-4)
        # @option options [Integer] :pb Position bits (0-4)
        # @option options [Boolean] :write_size Write actual size (false for standalone .lzma)
        # @option options [Boolean] :sdk_compatible Use SDK-compatible encoding (default: true)
        # @option options [Boolean] :xz_compatible Use XZ-compatible encoding (default: false)
        # @option options [Boolean] :raw_mode Skip header for raw LZMA encoding (for 7-Zip/LZMA2)
        def initialize(output, options = {})
          @output = output
          @dict_size = options[:dict_size] || (1 << 16) # 64KB default
          @lc = options[:lc] || 3
          @lp = options[:lp] || 0
          @pb = options[:pb] || 2
          @write_size = options.fetch(:write_size, true)
          @xz_compatible = options.fetch(:xz_compatible, false)
          @sdk_compatible = options.fetch(:sdk_compatible, !@xz_compatible)
          @raw_mode = options.fetch(:raw_mode, false)

          validate_parameters

          # Factory pattern: create implementation based on mode
          @impl = if @xz_compatible
                    # Use XzEncoder (XZ Utils LZMA)
                    XzEncoderAdapter.new(output, options)
                  else
                    # Use SdkEncoder (7-Zip LZMA SDK compatible) - DEFAULT
                    Implementations::SevenZip::LZMA::Encoder.new(output,
                                                                 options)
                  end
        end

        # Encode a stream of data
        #
        # @param input [String, IO] Input data to compress
        # @return [Array<String, Integer>, void] Tuple of [data, decode_bytes] in raw mode, void otherwise
        def encode_stream(input)
          @impl.encode_stream(input)
        end

        private

        # Validate encoding parameters
        #
        # @return [void]
        # @raise [ArgumentError] If parameters are invalid
        def validate_parameters
          raise ArgumentError, "lc must be 0-8" unless @lc.between?(0, 8)
          raise ArgumentError, "lp must be 0-4" unless @lp.between?(0, 4)
          raise ArgumentError, "pb must be 0-4" unless @pb.between?(0, 4)
          return if @dict_size.between?(DICT_SIZE_MIN, DICT_SIZE_MAX)

          raise ArgumentError, "Invalid dictionary size"
        end
      end

      # Adapter for XzEncoder to match SdkEncoder interface
      #
      # XzEncoder has a different interface (encode(input, output) vs encode_stream(input)).
      # This adapter wraps XzEncoder to provide the same interface as SdkEncoder.
      class XzEncoderAdapter
        # Initialize adapter
        #
        # @param output [IO] Output stream
        # @param options [Hash] Encoding options
        def initialize(output, options = {})
          @output = output
          @options = options
          @xz_encoder = XzEncoder.new(options)
          @bytes_for_decode = nil
        end

        # Encode stream (matches SdkEncoder interface)
        #
        # @param input [String, IO] Input data to compress
        # @return [Array<String, Integer>] Tuple of [compressed_data, decode_bytes]
        def encode_stream(input)
          input_data = input.is_a?(String) ? input : input.read
          @bytes_for_decode = @xz_encoder.encode(input_data, @output)
          [@output.string, @bytes_for_decode]
        end

        # Get bytes for decode (for LZMA2 compatibility)
        #
        # @return [Integer] Number of bytes decoder will consume
        def bytes_for_decode
          @bytes_for_decode || @output.string.bytesize
        end
      end
    end
  end
end
