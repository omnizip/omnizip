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
      # Abstract base class for LZMA2 decoders.
      #
      # This class defines the common interface and shared functionality
      # for all LZMA2 decoder implementations (XZ Utils, 7-Zip, etc.).
      #
      # Subclasses must implement the {#decode} method.
      #
      # @abstract Subclasses must implement {#decode}
      class LZMA2DecoderBase
        attr_reader :dict_size

        # Initialize the LZMA2 decoder.
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options
        # @option options [Integer] :dict_size Dictionary size (read from properties)
        def initialize(input, options = {})
          @input = input
          # Dictionary size will be read from LZMA2 property byte by subclasses
          @dict_size = options.fetch(:dict_size, nil)
        end

        # Decode LZMA2 compressed data.
        #
        # Subclasses must implement this method to provide the specific
        # decoding logic for their implementation (XZ Utils, 7-Zip, etc.).
        #
        # @param output [IO] Output stream for decompressed data
        # @raise [NotImplementedError] Always raised in base class
        # @return [void]
        def decode(output = nil)
          raise NotImplementedError,
                "#{self.class} must implement #decode"
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
