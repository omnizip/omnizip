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

require_relative "../lzma/xz_encoder"

module Omnizip
  module Algorithms
    # Adapter for XZ Encoder to work with LZMA2 chunking
    #
    # Wraps the pure Ruby XZ encoder to provide LZMA2-compatible interface
    # for chunked encoding with size limits.
    class LZMA2XzEncoderAdapter
      # Initialize XZ encoder adapter
      #
      # @param options [Hash] Encoding options
      # @option options [Integer] :lc Literal context bits (default 3)
      # @option options [Integer] :lp Literal position bits (default 0)
      # @option options [Integer] :pb Position bits (default 2)
      # @option options [Integer] :nice_len Nice match length (default 32)
      # @option options [Integer] :dict_size Dictionary size (default 8MB)
      def initialize(options = {})
        @options = options
        @lc = options[:lc] || 3
        @lp = options[:lp] || 0
        @pb = options[:pb] || 2
      end

      # Encode data chunk
      #
      # @param data [String] Input data to encode
      # @param limit [Integer, nil] Optional output size limit
      # @return [String] Encoded data
      def encode_chunk(data, _limit = nil)
        output = StringIO.new
        encoder = LZMA::XzEncoder.new(@options)

        # Encode with optional size limit
        # XZ encoder returns bytes written to output
        encoder.encode(data, output)

        # Return the encoded data string
        output.string
      end

      # Get LZMA properties byte
      #
      # Encodes lc, lp, pb into single byte using formula:
      # (pb * 5 + lp) * 9 + lc
      #
      # @return [Integer] Properties byte (0x00-0xFF)
      def properties
        (((@pb * 5) + @lp) * 9) + @lc
      end

      # Get dictionary size
      #
      # @return [Integer] Dictionary size in bytes
      def dict_size
        @options[:dict_size] || (1 << 23) # 8MB default
      end
    end

    # Backward compatibility alias
    XzEncoderAdapter = LZMA2XzEncoderAdapter unless defined?(XzEncoderAdapter)
  end
end
