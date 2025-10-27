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
      #   dictSize = 2^(11 + props/2) + 2^11 * (props % 2)
      #
      # This gives sizes from 4KB (props=0) to 4GB (props=40)
      class Properties
        include Constants

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
          (PROP_DICT_MIN..PROP_DICT_MAX).each do |prop|
            size = self.class.decode_dict_size(prop)
            return prop if size >= dict_size
          end

          # If we couldn't find a suitable prop, use maximum
          PROP_DICT_MAX
        end

        # Decode property byte to dictionary size
        #
        # @param prop [Integer] Property byte
        # @return [Integer] Dictionary size in bytes
        def self.decode_dict_size(prop)
          # Formula: dictSize = 2^(11 + prop/2) + 2^11 * (prop % 2)
          base_exp = 11 + (prop / 2)
          base_size = 1 << base_exp

          if prop.odd?
            # Add extra 2^11 for odd values
            base_size + (1 << 11)
          else
            base_size
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
          unless size.between?(DICT_SIZE_MIN, DICT_SIZE_MAX)
            raise ArgumentError,
                  "Dictionary size must be between #{DICT_SIZE_MIN} " \
                  "and #{DICT_SIZE_MAX}"
          end
          size
        end

        # Validate property byte
        #
        # @param prop [Integer] Property byte to validate
        # @return [void]
        # @raise [ArgumentError] If property byte is invalid
        def self.validate_prop_byte(prop)
          return if prop.between?(PROP_DICT_MIN, PROP_DICT_MAX)

          raise ArgumentError,
                "Property byte must be between #{PROP_DICT_MIN} " \
                "and #{PROP_DICT_MAX}"
        end
      end
    end
  end
end
