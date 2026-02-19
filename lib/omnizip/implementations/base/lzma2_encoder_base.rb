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
      # Abstract base class for LZMA2 encoders.
      #
      # This class defines the common interface and shared functionality
      # for all LZMA2 encoder implementations (XZ Utils, 7-Zip, etc.).
      #
      # LZMA2 is an improved version of LZMA that supports:
      # - Uncompressed chunks for incompressible data
      # - Dictionary/state resets for better compression
      # - Simpler chunk format
      #
      # Subclasses must implement the {#encode} method.
      #
      # @abstract Subclasses must implement {#encode}
      class LZMA2EncoderBase
        attr_reader :dict_size, :lc, :lp, :pb

        # Maximum uncompressed size per LZMA2 chunk (2MB)
        UNCOMPRESSED_MAX = 1 << 21
        # Maximum compressed size per LZMA2 chunk (64KB)
        COMPRESSED_MAX = 1 << 16

        # Initialize the LZMA2 encoder.
        #
        # @param options [Hash] Encoding options
        # @option options [Integer] :dict_size Dictionary size (default: 8MB)
        # @option options [Integer] :lc Literal context bits (default: 3)
        # @option options [Integer] :lp Literal position bits (default: 0)
        # @option options [Integer] :pb Position bits (default: 2)
        # @option options [Boolean] :standalone Write property byte at start (default: true)
        def initialize(options = {})
          @dict_size = options.fetch(:dict_size, 8 * 1024 * 1024)
          @lc = options.fetch(:lc, 3)
          @lp = options.fetch(:lp, 0)
          @pb = options.fetch(:pb, 2)
          @standalone = options.fetch(:standalone, true)

          validate_parameters!
        end

        # Encode data using LZMA2.
        #
        # Subclasses must implement this method to provide the specific
        # encoding logic for their implementation (XZ Utils, 7-Zip, etc.).
        #
        # @param data [String] Input data to compress
        # @raise [NotImplementedError] Always raised in base class
        # @return [String] Compressed data
        def encode(data)
          raise NotImplementedError,
                "#{self.class} must implement #encode"
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

        # Check if standalone mode is enabled.
        #
        # @return [Boolean] true if property byte should be written
        def standalone?
          @standalone
        end

        private

        # Validate LZMA2 parameters.
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

          # LZMA2 dictionary size constraints (from XZ Utils)
          min_dict = 4096
          max_dict = 1 << 28

          unless @dict_size.between?(min_dict, max_dict)
            raise ArgumentError,
                  "dict_size must be between #{min_dict} and #{max_dict}, got #{@dict_size}"
          end
        end
      end
    end
  end
end
