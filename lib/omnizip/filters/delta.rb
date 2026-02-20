# frozen_string_literal: true

#
# Copyright (C) 2024-2025 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

require_relative "../filter"

module Omnizip
  module Filters
    # Delta filter for multimedia and database preprocessing.
    #
    # This filter computes byte-wise differences between adjacent bytes
    # at a specified distance. It is particularly effective for
    # multimedia files (WAV, BMP) and database dumps where adjacent
    # bytes often have small differences.
    #
    # The filter uses wrap-around arithmetic (modulo 256) and is
    # fully reversible.
    #
    # Filter IDs by format:
    # - XZ: 0x03
    # - 7-Zip: 0x03
    class Delta < ::Omnizip::Filter
      # Default distance for delta calculation (audio/single channel)
      DEFAULT_DISTANCE = 1

      # Maximum allowed distance value
      MAX_DISTANCE = 256

      # Byte modulo for wrap-around arithmetic
      BYTE_MODULO = 256

      # Filter ID for XZ format
      XZ_FILTER_ID = 0x03

      # Filter ID for 7-Zip format
      SEVEN_ZIP_FILTER_ID = 0x03

      attr_reader :distance

      # Initialize Delta filter with specified distance.
      #
      # Supports both positional and keyword argument styles:
      #   Delta.new(3)           # positional
      #   Delta.new(distance: 3) # keyword
      #
      # @param distance [Integer] Byte distance for delta calculation
      #   - 1: Audio/single channel data
      #   - 2: Stereo 16-bit audio
      #   - 3: RGB image data (24-bit)
      #   - 4: RGBA image data (32-bit) or 32-bit integers
      # @raise [ArgumentError] If distance is invalid
      def initialize(distance_arg = DEFAULT_DISTANCE,
distance: DEFAULT_DISTANCE)
        # Support both positional and keyword argument styles
        # If called with Delta.new(3), distance_arg=3, distance=DEFAULT (keyword not used)
        # If called with Delta.new(distance: 3), distance_arg=DEFAULT, distance=3
        dist = if distance == DEFAULT_DISTANCE
                 distance_arg
               else
                 distance
               end

        validate_distance(dist)
        @distance = dist
        super(architecture: :delta, name: "Delta")
      end

      # Get filter ID for specific format
      #
      # @param format [Symbol] Format identifier (:seven_zip, :xz)
      # @return [Integer] Format-specific filter ID
      # @raise [ArgumentError] If format is not supported
      def id_for_format(format)
        case format
        when :seven_zip
          SEVEN_ZIP_FILTER_ID
        when :xz
          XZ_FILTER_ID
        else
          raise ArgumentError,
                "Unknown format: #{format}. Supported: :seven_zip, :xz"
        end
      end

      # Encode (preprocess) data by computing forward differences.
      #
      # For each byte at position i >= distance:
      #   new[i] = (old[i] - old[i - distance]) mod 256
      #
      # Bytes before the distance remain unchanged (no previous value).
      #
      # @param data [String] Binary data to encode
      # @param position [Integer] Current stream position (unused for
      #   Delta)
      # @return [String] Encoded binary data
      def encode(data, _position = 0)
        return data.dup if data.empty?

        source = data.b
        result = data.b
        size = data.bytesize

        # Process bytes starting from distance
        distance.upto(size - 1) do |i|
          current = source.getbyte(i)
          previous = source.getbyte(i - distance)
          # Compute difference with wrap-around
          diff = (current - previous) & 0xFF
          result.setbyte(i, diff)
        end

        result
      end

      # Decode (postprocess) data by restoring from differences.
      #
      # For each byte at position i >= distance:
      #   old[i] = (new[i] + old[i - distance]) mod 256
      #
      # Bytes before the distance remain unchanged (already original).
      #
      # @param data [String] Binary data to decode
      # @param position [Integer] Current stream position (unused for
      #   Delta)
      # @return [String] Decoded binary data
      def decode(data, _position = 0)
        return data.dup if data.empty?

        source = data.b
        result = data.b
        size = data.bytesize

        # Process bytes starting from distance
        distance.upto(size - 1) do |i|
          diff = source.getbyte(i)
          previous = result.getbyte(i - distance)
          # Restore original value with wrap-around
          original = (diff + previous) & 0xFF
          result.setbyte(i, original)
        end

        result
      end

      class << self
        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "Delta",
            description: "Byte-wise difference filter for multimedia " \
                         "and database preprocessing",
            typical_usage: "WAV audio, BMP images, database dumps",
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
          raise ArgumentError, "Distance must be an integer"
        end

        if dist < 1
          raise ArgumentError,
                "Distance must be at least 1, got #{dist}"
        end

        return unless dist > MAX_DISTANCE

        raise ArgumentError,
              "Distance must not exceed #{MAX_DISTANCE}, got #{dist}"
      end
    end
  end
end
