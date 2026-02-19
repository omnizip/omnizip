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

module Omnizip
  module Algorithms
    class LZMA2
      # LZMA2 Properties - handles dictionary size encoding/decoding
      #
      # The LZMA2 format uses a single property byte that encodes the
      # dictionary size. This is more compact than LZMA's multiple
      # property bytes.
      #
      # Dictionary size encoding formula:
      #   dictSize = (2 | (props & 1)) << (props / 2 + 11)
      #
      # This gives sizes from 4KB (props=0) to 4GB (props=40)
      #
      # Note: In XZ format, the LZMA2 filter properties byte contains ONLY
      # the dictionary size encoding. The lc/lp/pb parameters are encoded
      # in the LZMA chunk properties (inside the compressed data).
      class Properties
        include LZMA2Const

        attr_reader :dict_size, :prop_byte

        # Initialize properties from dictionary size
        #
        # @param dict_size [Integer] Dictionary size in bytes
        def initialize(dict_size)
          @dict_size = validate_dict_size(dict_size)
          @prop_byte = encode_dict_size(@dict_size)
        end

        # Create properties from property byte
        #
        # @param prop_byte [Integer] Encoded property byte
        # @return [Properties] New properties instance
        def self.from_byte(prop_byte)
          validate_prop_byte(prop_byte)
          dict_size = decode_dict_size(prop_byte)
          new(dict_size)
        end

        # Encode dictionary size to property byte
        #
        # @param dict_size [Integer] Dictionary size
        # @return [Integer] Property byte value
        def encode_dict_size(dict_size)
          # Find the smallest prop value that gives >= dict_size
          # Valid range for property byte is 0-40 (per XZ spec)
          (0..40).each do |prop|
            size = self.class.decode_dict_size(prop)
            return prop if size >= dict_size
          end

          # If we couldn't find a suitable prop, use maximum
          40
        end

        # Decode property byte to dictionary size
        #
        # XZ Utils formula from lzma_lzma2_props_decode (lzma2_decoder.c:290-302):
        #   dict_size = (2 | (props & 1)) << (props / 2 + 11)
        #
        # For even props: dict_size = 2 * 2^((props/2) + 11) = 2^((props/2) + 12)
        # For odd props: dict_size = 3 * 2^((props-1)/2 + 11)
        #
        # @param prop [Integer] Property byte
        # @return [Integer] Dictionary size in bytes
        def self.decode_dict_size(prop)
          # XZ Utils formula: dict_size = (2 | (prop & 1)) << (prop / 2 + 11)
          base = 2 | (prop & 1)
          base << ((prop / 2) + 11)
        end

        # Encode properties to property byte
        # This is for standalone LZMA2 files where the property byte
        # encodes both dictionary size and lc/lp/pb parameters
        #
        # @param dict_size [Integer] Dictionary size
        # @param lc [Integer] Literal context bits
        # @param lp [Integer] Literal position bits
        # @param pb [Integer] Position bits
        # @return [Integer] Property byte value
        def self.encode(dict_size, _lc = 3, _lp = 0, _pb = 2)
          # For standalone LZMA2 files, we only encode the dictionary size
          # The lc/lp/pb parameters are encoded in the LZMA chunk properties instead
          validate_prop_byte_range(dict_size)
          encode_dict_size_to_byte(dict_size)
        end

        # Encode dictionary size to property byte
        #
        # @param dict_size [Integer] Dictionary size
        # @return [Integer] Property byte value
        def self.encode_dict_size_to_byte(dict_size)
          # Find the smallest prop value that gives >= dict_size
          (0..40).each do |prop|
            size = decode_dict_size(prop)
            return prop if size >= dict_size
          end
          40
        end

        # Validate dictionary size for property byte encoding
        #
        # @param size [Integer] Dictionary size to validate
        # @raise [ArgumentError] If size is invalid
        def self.validate_prop_byte_range(size)
          unless size.between?(DICT_SIZE_MIN, DICT_SIZE_MAX)
            raise ArgumentError,
                  "Dictionary size must be between #{DICT_SIZE_MIN} " \
                  "and #{DICT_SIZE_MAX}"
          end
        end

        # Get the actual dictionary size (may differ from requested)
        #
        # @return [Integer] Actual dictionary size
        def actual_dict_size
          self.class.decode_dict_size(@prop_byte)
        end

        private

        # Validate dictionary size
        #
        # @param size [Integer] Dictionary size to validate
        # @return [Integer] Validated size
        # @raise [ArgumentError] If size is invalid
        def validate_dict_size(size)
          # LZMA2 practical maximum is 2GB due to implementation limitations
          # The spec allows up to 4GB, but practical limits are lower
          # Maximum is (1 << 31) - 1 due to signed 32-bit integer limits
          max_size = [DICT_SIZE_MAX, (1 << 31) - 1].min
          unless size.between?(DICT_SIZE_MIN, max_size)
            raise ArgumentError,
                  "Dictionary size must be between #{DICT_SIZE_MIN} " \
                  "and #{max_size}"
          end
          size
        end

        # Validate property byte
        #
        # @param prop [Integer] Property byte to validate
        # @return [void]
        # @raise [ArgumentError] If property byte is invalid
        def self.validate_prop_byte(prop)
          return if prop.between?(0, 40)

          raise ArgumentError,
                "Property byte must be between 0 and 40"
        end
      end
    end
  end
end
