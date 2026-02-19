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
  module Implementations
    module Base
      # Abstract base class for LZMA decoders.
      #
      # This class defines the common interface and shared functionality
      # for all LZMA decoder implementations (XZ Utils, 7-Zip SDK, etc.).
      #
      # Subclasses must implement the {#decode_stream} method.
      #
      # @abstract Subclasses must implement {#decode_stream}
      class LZMADecoderBase
        attr_reader :lc, :lp, :pb, :dict_size, :uncompressed_size, :input

        # Initialize the LZMA decoder.
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options
        # @option options [Integer] :lc Literal context bits (read from header)
        # @option options [Integer] :lp Literal position bits (read from header)
        # @option options [Integer] :pb Position bits (read from header)
        # @option options [Integer] :dict_size Dictionary size (read from header)
        # @option options [Integer] :uncompressed_size Uncompressed size
        def initialize(input, options = {})
          @input = input
          # Parameters will be read from LZMA header by subclasses
          @lc = options.fetch(:lc, nil)
          @lp = options.fetch(:lp, nil)
          @pb = options.fetch(:pb, nil)
          @dict_size = options.fetch(:dict_size, nil)
          @uncompressed_size = options.fetch(:uncompressed_size, nil)
        end

        # Decode a stream of compressed data.
        #
        # Subclasses must implement this method to provide the specific
        # decoding logic for their implementation (XZ Utils, 7-Zip, etc.).
        #
        # @param output [IO] Output stream for decompressed data
        # @raise [NotImplementedError] Always raised in base class
        # @return [void]
        def decode_stream(output = nil)
          raise NotImplementedError,
                "#{self.class} must implement #decode_stream"
        end

        # Get the implementation identifier.
        #
        # Subclasses must implement this to return a symbol identifying
        # their implementation (e.g., :xz_utils, :seven_zip).
        #
        # @raise [NotImplementedError] Always raised in base class
        # @return [Symbol] Implementation identifier
        def implementation_name
          raise NotImplementedError,
                "#{self.class} must implement #implementation_name"
        end
      end
    end
  end
end
