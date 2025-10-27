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

require_relative "constants"
require_relative "stream_data"

module Omnizip
  module Filters
    # BCJ2 encoder - splits data into 4 streams.
    #
    # NOTE: BCJ2 encoding is extremely complex and is not yet
    # implemented. This is primarily needed for compression,
    # while decoding (decompression) is the more common use case.
    #
    # BCJ2 encoding requires:
    # - Range encoder implementation
    # - Proper probability model management
    # - Stream splitting logic
    # - Address conversion to absolute
    #
    # This will be implemented in a future version.
    class Bcj2Encoder
      include Bcj2Constants

      # Initialize encoder.
      #
      # @param data [String] Binary data to encode
      # @param position [Integer] Starting instruction pointer
      def initialize(data, position = 0)
        @data = data
        @position = position
      end

      # Encode data into 4 streams.
      #
      # @raise [NotImplementedError] BCJ2 encoding not yet impl
      # @return [Bcj2StreamData] The 4 output streams
      def encode
        raise NotImplementedError,
              "BCJ2 encoding is not yet implemented. " \
              "BCJ2 is primarily used for decompression. " \
              "For compression, use the simpler BCJ-x86 filter."
      end
    end
  end
end
