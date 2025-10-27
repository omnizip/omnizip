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

module Omnizip
  module Filters
    # Abstract base class for preprocessing filters.
    #
    # Filters are reversible transformations applied to data before
    # compression to improve compression ratios. They are particularly
    # effective for executable files and other structured data.
    #
    # All filter implementations should inherit from this class and
    # implement the required methods.
    class FilterBase
      # Encode (preprocess) data for compression.
      #
      # This method transforms data to make it more compressible. The
      # transformation must be reversible - decode(encode(data)) == data.
      #
      # @param data [String] Binary data to encode
      # @param position [Integer] Current position in stream (for
      #   multi-block filtering)
      # @raise [NotImplementedError] Must be implemented by subclass
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        raise NotImplementedError,
              "#{self.class} must implement #encode"
      end

      # Decode (postprocess) data after decompression.
      #
      # This method reverses the encoding transformation, restoring
      # original data.
      #
      # @param data [String] Binary data to decode
      # @param position [Integer] Current position in stream (for
      #   multi-block filtering)
      # @raise [NotImplementedError] Must be implemented by subclass
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        raise NotImplementedError,
              "#{self.class} must implement #decode"
      end

      class << self
        # Get metadata about this filter.
        #
        # @raise [NotImplementedError] Must be implemented by subclass
        # @return [Hash] Filter metadata including name, description
        def metadata
          raise NotImplementedError,
                "#{self} must implement .metadata"
        end
      end
    end
  end
end
