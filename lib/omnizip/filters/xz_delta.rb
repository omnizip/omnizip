# frozen_string_literal: true

#
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
#
# XZ Utils Delta filter implementation.
#
# This is the XZ Utils Delta filter (filter ID 0x03), which is DIFFERENT
# from the 7-Zip Delta filter. Both compute byte-wise differences but use
# different algorithms:
#
# - 7-Zip Delta: Simple forward difference (new[i] = old[i] - old[i-distance])
# - XZ Utils Delta: Uses a 256-byte circular history buffer
#
# Reference: /Users/mulgogi/src/external/xz/src/liblzma/delta/
#
# Algorithm summary:
# - Maintains a 256-byte circular history buffer
# - Encoder: out[i] = in[i] - history[(distance + pos) & 0xFF]
# - Decoder: out[i] = in[i] + history[(distance + pos) & 0xFF]
# - history[pos & 0xFF] = processed_byte (updated in both encode/decode)
# - pos decrements each byte, wrapping via & 0xFF
#
# The distance parameter (1-256) determines how far back in the history
# to look for the delta reference value.

module Omnizip
  module Filters
    # XZ Utils Delta filter.
    #
    # This filter computes byte-wise differences using a 256-byte circular
    # history buffer. It is particularly effective for:
    # - Stereo audio (distance=4 for 16-bit samples)
    # - RGB images (distance=3)
    # - RGBA images (distance=4)
    # - Multi-channel data with regular patterns
    #
    # This is DIFFERENT from the 7-Zip Delta filter which uses simple
    # forward differences without a history buffer.
    #
    # Reference: XZ Utils delta_encoder.c, delta_decoder.c
    class XzDeltaFilter
      # Filter ID for XZ format
      FILTER_ID = 0x03

      # Minimum distance value (XZ Utils LZMA_DELTA_DIST_MIN)
      DELTA_DIST_MIN = 1

      # Maximum distance value (XZ Utils LZMA_DELTA_DIST_MAX)
      DELTA_DIST_MAX = 256

      # History buffer size (always 256 bytes in XZ Utils)
      HISTORY_SIZE = 256

      # Delta type (only BYTE is supported in XZ Utils)
      DELTA_TYPE_BYTE = 0

      attr_reader :distance

      # Initialize the Delta filter.
      #
      # @param distance [Integer] Byte distance for delta calculation (1-256)
      # @raise [ArgumentError] If distance is invalid
      def initialize(distance = DELTA_DIST_MIN)
        validate_distance(distance)
        @distance = distance
        # Initialize state (matches XZ Utils lzma_delta_coder_init)
        @pos = 0
        @history = ("\x00" * HISTORY_SIZE).b
      end

      # Encode (preprocess) data by computing forward differences.
      #
      # For each byte:
      #   tmp = history[(distance + pos) & 0xFF]
      #   history[pos & 0xFF] = in[i]
      #   out[i] = in[i] - tmp (mod 256)
      #   pos--
      #
      # Reference: XZ Utils delta_encoder.c:copy_and_encode
      #
      # @param data [String] Binary data to encode
      # @return [String] Encoded binary data
      def encode(data)
        return data.dup.b if data.empty?

        result = data.dup.b
        data.bytes.each_with_index do |byte, i|
          # Get historical value from distance positions back
          tmp = @history.getbyte((@distance + @pos) & 0xFF)

          # Store current byte in history
          @history.setbyte(@pos & 0xFF, byte)

          # Output is the difference
          result.setbyte(i, (byte - tmp) & 0xFF)

          # Move position backward (wraps via & 0xFF)
          @pos = (@pos - 1) & 0xFF
        end

        result
      end

      # Decode (postprocess) data by restoring from differences.
      #
      # For each byte:
      #   buffer[i] += history[(distance + pos) & 0xFF] (mod 256)
      #   history[pos & 0xFF] = buffer[i]
      #   pos--
      #
      # Reference: XZ Utils delta_decoder.c:decode_buffer
      #
      # @param data [String] Binary data to decode
      # @return [String] Decoded binary data
      def decode(data)
        return data.dup.b if data.empty?

        result = data.dup.b
        data.bytes.each_with_index do |byte, i|
          # Get historical value from distance positions back
          tmp = @history.getbyte((@distance + @pos) & 0xFF)

          # Restore original value by adding the difference
          result.setbyte(i, (byte + tmp) & 0xFF)

          # Store restored byte in history
          @history.setbyte(@pos & 0xFF, result.getbyte(i))

          # Move position backward (wraps via & 0xFF)
          @pos = (@pos - 1) & 0xFF
        end

        result
      end

      # Reset the filter state.
      #
      # This clears the history buffer and resets position to 0.
      # Used when initializing a new filter chain.
      #
      # @return [void]
      def reset
        @pos = 0
        @history = ("\x00" * HISTORY_SIZE).b
      end

      class << self
        # Decode properties byte to get distance.
        #
        # XZ Utils encodes distance as: props[0] = dist - 1
        # So we decode as: dist = props[0] + 1
        #
        # Reference: XZ Utils delta_decoder.c:lzma_delta_props_decode
        #
        # @param properties [String] Properties byte (1 byte)
        # @return [Integer] Distance value (1-256)
        # @raise [ArgumentError] If properties size is invalid
        def decode_properties(properties)
          unless properties.is_a?(String) && properties.bytesize == 1
            raise ArgumentError,
                  "Delta filter requires exactly 1 property byte, got #{properties&.bytesize}"
          end

          props_byte = properties.getbyte(0)
          # XZ Utils: opt->dist = props[0] + LZMA_DELTA_DIST_MIN
          # where LZMA_DELTA_DIST_MIN = 1
          distance = props_byte + DELTA_DIST_MIN

          # Validate distance is in valid range (inline for class method)
          unless distance.between?(DELTA_DIST_MIN, DELTA_DIST_MAX)
            raise ArgumentError,
                  "Invalid distance #{distance}, must be between #{DELTA_DIST_MIN} and #{DELTA_DIST_MAX}"
          end

          distance
        end

        # Encode distance to properties byte.
        #
        # XZ Utils encodes distance as: props[0] = dist - 1
        #
        # Reference: XZ Utils delta_encoder.c:lzma_delta_props_encode
        #
        # @param distance [Integer] Distance value (1-256)
        # @return [String] Properties byte (1 byte)
        # @raise [ArgumentError] If distance is invalid
        def encode_properties(distance)
          # Validate distance (inline for class method)
          unless distance.is_a?(Integer)
            raise ArgumentError,
                  "Distance must be an integer, got #{distance.class}"
          end

          unless distance.between?(DELTA_DIST_MIN, DELTA_DIST_MAX)
            raise ArgumentError,
                  "Distance must be between #{DELTA_DIST_MIN} and #{DELTA_DIST_MAX}, got #{distance}"
          end

          # XZ Utils: out[0] = opt->dist - LZMA_DELTA_DIST_MIN
          # where LZMA_DELTA_DIST_MIN = 1
          props_byte = distance - DELTA_DIST_MIN

          [props_byte].pack("C")
        end

        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "XZ Delta",
            description: "XZ Utils Delta filter with 256-byte circular history buffer",
            filter_id: FILTER_ID,
            typical_usage: "WAV audio (distance=4), BMP images (distance=3), " \
                           "multi-channel data with regular patterns",
          }
        end
      end

      private

      # Validate distance parameter.
      #
      # @param dist [Integer] Distance value to validate
      # @raise [ArgumentError] If distance is invalid
      # @return [void]
      def validate_distance(dist)
        unless dist.is_a?(Integer)
          raise ArgumentError, "Distance must be an integer, got #{dist.class}"
        end

        unless dist.between?(DELTA_DIST_MIN, DELTA_DIST_MAX)
          raise ArgumentError,
                "Distance must be between #{DELTA_DIST_MIN} and #{DELTA_DIST_MAX}, got #{dist}"
        end
      end
    end
  end
end
