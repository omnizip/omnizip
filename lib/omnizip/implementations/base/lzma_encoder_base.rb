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
      # Abstract base class for LZMA encoders.
      #
      # This class defines the common interface and shared functionality
      # for all LZMA encoder implementations (XZ Utils, 7-Zip SDK, etc.).
      #
      # Subclasses must implement the {#encode_stream} method.
      #
      # @abstract Subclasses must implement {#encode_stream}
      class LZMAEncoderBase
        attr_reader :lc, :lp, :pb, :dict_size, :output

        # Initialize the LZMA encoder.
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :lc Literal context bits (0-8, default: 3)
        # @option options [Integer] :lp Literal position bits (0-4, default: 0)
        # @option options [Integer] :pb Position bits (0-4, default: 2)
        # @option options [Integer] :dict_size Dictionary size (default: 64KB)
        # @raise [ArgumentError] If parameters are invalid
        def initialize(output, options = {})
          @output = output
          @lc = options.fetch(:lc, 3)
          @lp = options.fetch(:lp, 0)
          @pb = options.fetch(:pb, 2)
          @dict_size = options.fetch(:dict_size, 1 << 16) # 64KB default

          validate_parameters!
        end

        # Encode a stream of data.
        #
        # Subclasses must implement this method to provide the specific
        # encoding logic for their implementation (XZ Utils, 7-Zip, etc.).
        #
        # @param data [String] Input data to compress
        # @raise [NotImplementedError] Always raised in base class
        # @return [void]
        def encode_stream(data)
          raise NotImplementedError,
                "#{self.class} must implement #encode_stream"
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

        private

        # Validate LZMA parameters.
        #
        # @raise [ArgumentError] If any parameter is out of valid range
        # @return [void]
        def validate_parameters!
          unless @lc.between?(0, 8)
            raise ArgumentError, "lc must be between 0 and 8, got #{@lc}"
          end

          unless @lp.between?(0, 4)
            raise ArgumentError, "lp must be between 0 and 4, got #{@lp}"
          end

          unless @pb.between?(0, 4)
            raise ArgumentError, "pb must be between 0 and 4, got #{@pb}"
          end

          unless @dict_size.between?(4096, 1 << 28)
            raise ArgumentError,
                  "dict_size must be between 4096 and 268435456, got #{@dict_size}"
          end
        end
      end
    end
  end
end
