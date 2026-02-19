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

require_relative "xz_utils_decoder"
require "stringio"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      #
      # Decoder for .lzma (LZMA_Alone) format
      #
      # This is the legacy LZMA_Alone format used by LZMA Utils 4.32.x.
      # It is DIFFERENT from the XZ format's LZMA2 compression!
      #
      # File format:
      # - Properties (1 byte): encodes lc, lp, pb values
      # - Dictionary size (4 bytes, little-endian)
      # - Uncompressed size (8 bytes, little-endian, UINT64_MAX = unknown)
      # - LZMA1 compressed stream (no footer, no CRC32)
      #
      # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/alone_decoder.c
      #
      # This decoder uses the same LZMA1 decoding engine as XZ format,
      # but with the legacy .lzma container format.
      #
      # @example Decode .lzma file
      #   data = File.binread("file.lzma")
      #   decoder = Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(StringIO.new(data))
      #   result = decoder.decode_stream
      #
      class LzmaAloneDecoder
        # Maximum valid uncompressed size (256 GiB)
        # From alone_decoder.c:118
        MAX_UNCOMPRESSED_SIZE = (1 << 38)

        # Property byte validation limits
        # From lzma_decoder.c:1218
        MAX_PROPERTY_BYTE = (((4 * 5) + 4) * 9) + 8 # = 233

        # Initialize the decoder with .lzma format input
        #
        # @param input [IO] Input stream of .lzma compressed data
        # @param options [Hash] Decoding options
        # @option options [Boolean] :picky If true, reject files unlikely to be .lzma (default: false)
        # @raise [RuntimeError] If header is invalid or unsupported
        def initialize(input, options = {})
          @input = input
          @picky = options.fetch(:picky, false)

          # Parse .lzma header
          parse_header

          # Create a wrapper stream that starts after the header
          # The XzUtilsDecoder will read from this stream
          @lzma_stream = @input

          # Initialize the XZ Utils LZMA decoder with parsed parameters
          # validate_size=true because .lzma format has explicit uncompressed size
          # allow_eopm=true because .lzma format allows EOPM even with known size
          # Reference: alone_decoder.c:127 (LZMA_LZMA1EXT_ALLOW_EOPM)
          @decoder = XzUtilsDecoder.new(@lzma_stream,
                                        lzma2_mode: true,
                                        validate_size: true,
                                        allow_eopm: true,
                                        lc: @lc,
                                        lp: @lp,
                                        pb: @pb,
                                        dict_size: @dict_size,
                                        uncompressed_size: @uncompressed_size)
        end

        # Decode the .lzma stream
        #
        # @param output [IO, nil] Optional output stream
        # @return [String, Integer] Decompressed data or bytes written
        def decode_stream(output = nil)
          # .lzma format allows EOPM even when uncompressed size is known
          # Reference: alone_decoder.c:127 (LZMA_LZMA1EXT_ALLOW_EOPM)
          @decoder.decode_stream(output, check_rc_finished: false)
        end

        private

        # Parse .lzma format header
        #
        # Format (from alone_decoder.c):
        # - Properties (1 byte): lc/lp/pb encoded
        # - Dictionary size (4 bytes, little-endian)
        # - Uncompressed size (8 bytes, little-endian, UINT64_MAX = unknown)
        #
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/alone_decoder.c
        #
        # @return [void]
        # @raise [RuntimeError] If header is invalid
        def parse_header
          # Step 1: Parse properties byte (SEQ_PROPERTIES)
          # Reference: alone_decoder.c:64-68
          props = @input.getbyte
          raise "Invalid .lzma header: missing properties byte" if props.nil?

          # Use XZ Utils property byte parsing
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma_decoder.c:1216-1228
          if props > MAX_PROPERTY_BYTE
            raise "Invalid .lzma header: properties byte #{props} exceeds maximum #{MAX_PROPERTY_BYTE}"
          end

          # Parse lc, lp, pb from properties byte
          # Formula: pb = props / (9 * 5); lp = (props % 45) / 9; lc = (props % 45) % 9
          @pb = props / (9 * 5)
          remainder = props - (@pb * 9 * 5)
          @lp = remainder / 9
          @lc = remainder - (@lp * 9)

          # Validate lc + lp <= 4 (LZMA_LCLP_MAX)
          # Reference: lzma_decoder.c:1227
          if @lc + @lp > 4
            raise "Invalid .lzma header: lc (#{@lc}) + lp (#{@lp}) exceeds maximum 4"
          end

          # Step 2: Parse dictionary size (SEQ_DICTIONARY_SIZE)
          # Reference: alone_decoder.c:71-96
          @dict_size = 0
          4.times do |i|
            byte = @input.getbyte
            raise "Incomplete .lzma header: missing dictionary size byte" if byte.nil?

            @dict_size |= (byte << (i * 8))
          end

          # Picky mode validation: only accept dictionary sizes that are
          # 2^n or 2^n + 2^(n-1). This reduces false positives.
          # Reference: alone_decoder.c:76-93
          if @picky && @dict_size != 0xFFFFFFFF
            # Check if dict_size is valid: 2^n or 2^n + 2^(n-1)
            d = @dict_size - 1
            d |= d >> 2
            d |= d >> 3
            d |= d >> 4
            d |= d >> 8
            d |= d >> 16
            d += 1

            if d != @dict_size
              raise "Invalid .lzma header: dictionary size #{@dict_size} is not 2^n or 2^n + 2^(n-1)"
            end
          end

          # Step 3: Parse uncompressed size (SEQ_UNCOMPRESSED_SIZE)
          # Reference: alone_decoder.c:102-120
          @uncompressed_size = 0
          8.times do |i|
            byte = @input.getbyte
            raise "Incomplete .lzma header: missing uncompressed size byte" if byte.nil?

            @uncompressed_size |= (byte << (i * 8))
          end

          # Picky mode validation: if uncompressed size is known (not UINT64_MAX),
          # it must be less than 256 GiB
          # Reference: alone_decoder.c:116-120
          if @picky && @uncompressed_size != 0xFFFFFFFFFFFFFFFF &&
              @uncompressed_size >= MAX_UNCOMPRESSED_SIZE
            raise "Invalid .lzma header: uncompressed size #{@uncompressed_size} exceeds maximum #{MAX_UNCOMPRESSED_SIZE}"
          end

          # Note: XZ Utils uses UINT64_MAX (0xFFFFFFFFFFFFFFFF) for unknown size
          # Our decoder treats this as "allow end-of-payload marker"
        end
      end
    end
  end
end
