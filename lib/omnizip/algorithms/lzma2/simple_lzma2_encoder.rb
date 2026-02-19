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

require "stringio"
require_relative "../lzma"
require_relative "constants"
require_relative "lzma2_chunk"
require_relative "properties"
require_relative "../../implementations/xz_utils/lzma2/encoder"

module Omnizip
  module Algorithms
    class LZMA2 < Algorithm
      # Simple LZMA2 encoder using XzEncoder internally
      #
      # This encoder uses the working XzEncoder for LZMA compression
      # and wraps the result in proper LZMA2 chunks.
      #
      # For 7-Zip format compatibility, we need to produce LZMA2 chunks
      # without a leading property byte (raw mode).
      class SimpleLZMA2Encoder
        # Maximum uncompressed size per LZMA2 chunk (2MB)
        UNCOMPRESSED_MAX = 1 << 21

        # Initialize the encoder
        # @param dict_size [Integer] Dictionary size (default: 8MB)
        # @param lc [Integer] Literal context bits (default: 3)
        # @param lp [Integer] Literal position bits (default: 0)
        # @param pb [Integer] Position bits (default: 2)
        # @param standalone [Boolean] If true, write property byte at start
        def initialize(
          dict_size: 8 * 1024 * 1024,
          lc: 3,
          lp: 0,
          pb: 2,
          standalone: true
        )
          @dict_size = dict_size
          @lc = lc
          @lp = lp
          @pb = pb
          @standalone = standalone
        end

        # Encode data into LZMA2 format
        # @param input_data [String] Input data to compress
        # @return [String] LZMA2 compressed data
        def encode(input_data)
          output = StringIO.new
          output.set_encoding(Encoding::BINARY)

          # Write property byte if standalone
          # LZMA2 property byte encodes dictionary size
          if @standalone
            prop_byte = encode_dict_size(@dict_size)
            output.putc(prop_byte)
          end

          # Use XZ Utils LZMA2 encoder for proper LZMA2 encoding (no EOS marker)
          # Pass standalone: false since SimpleLZMA2Encoder handles property byte
          encoder = Omnizip::Implementations::XZUtils::LZMA2::Encoder.new(
            dict_size: @dict_size,
            lc: @lc,
            lp: @lp,
            pb: @pb,
            standalone: false,
          )

          # Encode data - returns LZMA2 data as String (includes end marker)
          encoded = encoder.encode(input_data)

          # Write encoded data to output
          output.write(encoded)

          output.string
        end

        private

        # Encode dictionary size to LZMA2 property byte
        # @param dict_size [Integer] Dictionary size
        # @return [Integer] Property byte (0-40)
        def encode_dict_size(dict_size)
          # Clamp to valid range
          d = [dict_size, LZMA2Constants::DICT_SIZE_MIN].max

          # Calculate log2 of dict_size
          log2_size = 0
          temp = d
          while temp > 1
            log2_size += 1
            temp >>= 1
          end

          # Encoding formula for power-of-2 sizes:
          # d = 2 * (log2_size - 12)
          if d == (1 << log2_size)
            # Exact power of 2
            [(log2_size - 12) * 2, 40].min
          else
            # Between 2^n and 2^n + 2^(n-1), use odd encoding
            [((log2_size - 12) * 2) + 1, 40].min
          end
        end
      end
    end
  end
end
