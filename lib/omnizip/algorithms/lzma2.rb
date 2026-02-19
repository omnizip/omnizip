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

module Omnizip
  module Algorithms
    # LZMA2 compression algorithm
    # Improved version of LZMA with chunked format for better streaming
    class LZMA2 < Algorithm
    end
  end
end

# Now require the nested classes that will reopen LZMA2
require_relative "lzma2/constants"
require_relative "lzma2/properties"
require_relative "lzma2/lzma2_chunk"
require_relative "lzma2/encoder"
require_relative "../implementations/xz_utils/lzma2/decoder"
require_relative "../implementations/xz_utils/lzma2/encoder"
require_relative "../implementations/seven_zip/lzma2/encoder"
require_relative "lzma2/xz_encoder_adapter"

module Omnizip
  module Algorithms
    class LZMA2 < Algorithm
      class << self
        # Get algorithm metadata
        #
        # @return [Models::AlgorithmMetadata] Algorithm metadata
        def metadata
          Models::AlgorithmMetadata.new.tap do |meta|
            meta.name = "lzma2"
            meta.description = "LZMA2 compression with improved chunking format for better streaming"
            meta.version = "1.0.0"
            meta.supports_streaming = true
          end
        end
      end

      def initialize(options = {})
        super()
        @dict_size = options[:dict_size] || (8 * 1024 * 1024) # 8 MB default
        @lc = options[:lc] || 3
        @lp = options[:lp] || 0
        @pb = options[:pb] || 2
        @level = options[:level] || 6
        @raw_mode = options[:raw_mode] # For 7-Zip format (no property byte)
      end

      # Compress data using LZMA2
      def compress(input, output, options = {})
        # For 7-Zip format, use raw_mode (no property byte in data stream)
        # Default to true for backward compatibility with standalone LZMA2 files
        standalone = options.fetch(:standalone, true)
        options.fetch(:raw_mode, !standalone)

        encoder = LZMA2Encoder.new(
          dict_size: @dict_size,
          lc: @lc,
          lp: @lp,
          pb: @pb,
          standalone: standalone, # Write property byte only for standalone files
        )

        # Read input
        input_data = input.respond_to?(:read) ? input.read : input

        # Encode with LZMA2
        compressed = encoder.encode(input_data)

        # Write to output
        if output.respond_to?(:write)
          output.write(compressed)
        else
          output.replace(compressed)
        end
      end

      # Decompress LZMA2 data
      def decompress(input, output, options = {})
        # Read input data
        input_data = input.respond_to?(:read) ? input.read : input
        input_stream = StringIO.new(input_data)
        input_stream.set_encoding(Encoding::BINARY)

        # Determine raw_mode:
        # - For 7-Zip format: raw_mode=true, dict_size from coder properties
        # - For standalone LZMA2 files: raw_mode=false, dict_size from property byte
        raw_mode = options.fetch(:raw_mode, @raw_mode || false)
        dict_size = options.fetch(:dict_size, @dict_size)

        # Create decoder using XZ Utils implementation
        decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(
          input_stream,
          raw_mode: raw_mode,
          dict_size: dict_size,
        )

        # Decode LZMA2 data
        decompressed = decoder.decode_stream

        # Write to output
        if output.respond_to?(:write)
          output.write(decompressed)
        else
          output.replace(decompressed)
        end
      end

      # Encode dictionary size as single byte for LZMA2 properties
      def self.encode_dict_size(dict_size)
        LZMA2Encoder.encode_dict_size(dict_size)
      end
    end
  end
end

# Auto-register LZMA2 in algorithm registry
Omnizip::Algorithms::LZMA2.register_algorithm
