# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
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

require_relative "filter_base"
require_relative "bcj2/constants"
require_relative "bcj2/stream_data"
require_relative "bcj2/decoder"
require_relative "bcj2/encoder"

module Omnizip
  module Filters
    # BCJ2 filter for x86/x64 executables (4-stream variant).
    #
    # BCJ2 is an advanced version of BCJ that splits x86 executable code
    # into 4 separate streams for maximum compression:
    # - Main stream: Non-convertible bytes
    # - Call stream: CALL (0xE8) instruction addresses
    # - Jump stream: JUMP (0xE9) instruction addresses
    # - RC stream: Range coder probability data
    #
    # This provides better compression than simple BCJ at the cost of
    # increased complexity. BCJ2 requires special handling in archive
    # formats - the 4 streams must be stored and retrieved separately.
    #
    # NOTE: Currently only decoding (decompression) is implemented.
    # Encoding is extremely complex and will be added in a future version.
    # For compression use cases, the simpler BCJ-x86 filter is recommended.
    class Bcj2 < FilterBase
      # Encode is not currently supported for BCJ2.
      #
      # @param _data [String] Binary data to encode
      # @param _position [Integer] Current stream position
      # @raise [NotImplementedError] BCJ2 encoding not yet implemented
      # @return [String] Encoded binary data
      def encode(_data, _position = 0)
        raise NotImplementedError,
              "BCJ2 encoding is not yet implemented. " \
              "Use the simpler BCJ-x86 filter for compression, " \
              "or wait for a future version with BCJ2 encoding support."
      end

      # Decode (postprocess) BCJ2 data after decompression.
      #
      # This method expects the 4 BCJ2 streams to be provided in a
      # Bcj2StreamData object. In practice, this is called by the archive
      # format reader (e.g., 7z reader) which handles splitting the
      # compressed data into the 4 streams.
      #
      # @param data [Bcj2StreamData, String] The 4 BCJ2 streams or error
      # @param position [Integer] Current stream position
      # @raise [ArgumentError] If data is not a Bcj2StreamData object
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        unless data.is_a?(Bcj2StreamData)
          raise ArgumentError,
                "BCJ2 decode requires a Bcj2StreamData object with " \
                "4 streams. This is typically handled by the archive " \
                "format reader."
        end

        decoder = Bcj2Decoder.new(data, position)
        decoder.decode
      end

      class << self
        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "BCJ2",
            description: "Advanced 4-stream Branch/Call/Jump converter " \
                         "for x86/x64 executables",
            architecture: "x86/x64",
            streams: 4,
            complexity: "high",
            compression_quality: "maximum",
            limitations: "Encoding not yet implemented"
          }
        end
      end
    end
  end
end
