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

require "omnizip/algorithms"

module Omnizip
  module Algorithms
    # PPMd8 (PPMdI) compression algorithm
    #
    # PPMd8 is an improved variant of PPMd7 that adds:
    # - Multiple restoration methods (RESTART, CUT_OFF)
    # - Enhanced memory management with glue counting
    # - Improved context update algorithms
    # - Run-length encoding support for better repetition handling
    #
    # This implementation follows the PPMd8 specification from 7-Zip.
    class PPMd8 < PPMdBase
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/algorithms/ppmd8/constants"
      autoload :RestorationMethod, "omnizip/algorithms/ppmd8/restoration_method"
      autoload :Context, "omnizip/algorithms/ppmd8/context"
      autoload :Model, "omnizip/algorithms/ppmd8/model"
      autoload :Encoder, "omnizip/algorithms/ppmd8/encoder"
      autoload :Decoder, "omnizip/algorithms/ppmd8/decoder"

      # Cross-namespace dependencies - autoloaded
      autoload :RangeDecoder, "omnizip/algorithms/lzma/range_decoder"
      autoload :RangeEncoder, "omnizip/algorithms/lzma/range_encoder"

      include Constants

      # Algorithm metadata
      #
      # @return [AlgorithmMetadata] Metadata describing this algorithm
      def self.metadata
        Models::AlgorithmMetadata.new.tap do |m|
          m.name = "ppmd8"
          m.description = "PPMd8 (PPMdI) - Enhanced Prediction by " \
                          "Partial Matching with improved restoration"
          m.version = "1.0.0"
          m.supports_streaming = true
        end
      end

      protected

      # Create PPMd8 encoder
      #
      # @param output [IO] Output stream
      # @param options [Hash] Encoding options
      # @return [PPMd8::Encoder] Encoder instance
      def create_encoder(output, options)
        PPMd8::Encoder.new(output, options)
      end

      # Create PPMd8 decoder
      #
      # @param input [IO] Input stream
      # @param options [Hash] Decoding options
      # @return [PPMd8::Decoder] Decoder instance
      def create_decoder(input, options)
        PPMd8::Decoder.new(input, options)
      end
    end
  end
end

# Register algorithm with registry
Omnizip::AlgorithmRegistry.register(:ppmd8, Omnizip::Algorithms::PPMd8)
