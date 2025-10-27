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

module Omnizip
  module Algorithms
    # Base class for PPMd (Prediction by Partial Matching) algorithms
    #
    # This abstract base class provides common functionality for PPMd
    # variants (PPMd7, PPMd8, etc.) while allowing each variant to
    # implement its specific features.
    #
    # The design follows the Template Method pattern, where common
    # operations are defined here and variant-specific operations
    # are delegated to subclasses.
    class PPMdBase < Algorithm
      # Common constants for all PPMd variants
      module BaseConstants
        # Context order limits
        MIN_ORDER = 2
        MAX_ORDER = 16
        DEFAULT_ORDER = 6

        # Memory allocation
        MIN_MEM_SIZE = 1 << 20  # 1 MB
        MAX_MEM_SIZE = 1 << 30  # 1 GB
        DEFAULT_MEM_SIZE = 1 << 24 # 16 MB

        # Alphabet
        ALPHABET_SIZE = 256

        # Range coder constants
        TOP_VALUE = 1 << 24
        BOT_VALUE = 1 << 15
      end

      include BaseConstants

      # Compress data using PPMd variant
      #
      # @param input [IO, String] Input data to compress
      # @param output [IO, String] Output for compressed data
      # @param options [Hash] Compression options
      # @return [void]
      def compress(input, output, options = {})
        input = prepare_input(input)
        output = prepare_output(output)

        encoder = create_encoder(output, options)
        encoder.encode_stream(input)
      end

      # Decompress data using PPMd variant
      #
      # @param input [IO, String] Compressed input data
      # @param output [IO, String] Output for decompressed data
      # @param options [Hash] Decompression options
      # @return [void]
      def decompress(input, output, options = {})
        input = prepare_input(input)
        output = prepare_output(output)

        decoder = create_decoder(input, options)
        result = decoder.decode_stream

        output.write(result)
      end

      protected

      # Template method for creating encoder
      # Subclasses must implement this
      #
      # @param output [IO] Output stream
      # @param options [Hash] Encoding options
      # @return [Object] Encoder instance
      # @raise [NotImplementedError] if not implemented by subclass
      def create_encoder(output, options)
        raise NotImplementedError,
              "#{self.class} must implement #create_encoder"
      end

      # Template method for creating decoder
      # Subclasses must implement this
      #
      # @param input [IO] Input stream
      # @param options [Hash] Decoding options
      # @return [Object] Decoder instance
      # @raise [NotImplementedError] if not implemented by subclass
      def create_decoder(input, options)
        raise NotImplementedError,
              "#{self.class} must implement #create_decoder"
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
