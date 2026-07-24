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
  # Pipeline for chaining multiple filters together.
  #
  # Filters are applied in sequence during encoding, and in reverse
  # order during decoding. Position tracking is maintained across
  # the entire pipeline.
  class FilterPipeline
    attr_reader :filters

    # Initialize an empty filter pipeline.
    def initialize
      @filters = []
      @position = 0
    end

    # Add a filter to the pipeline.
    #
    # Filters are applied in the order they are added during encoding,
    # and in reverse order during decoding.
    #
    # @param filter [Filters::FilterBase] Filter instance to add
    # @return [self] For method chaining
    def add_filter(filter)
      @filters << filter
      self
    end

    # Check if pipeline has any filters.
    #
    # @return [Boolean] True if pipeline contains filters
    def empty?
      @filters.empty?
    end

    # Get number of filters in pipeline.
    #
    # @return [Integer] Number of filters
    def size
      @filters.size
    end

    # Encode (preprocess) data by applying all filters in order.
    #
    # Filters are applied sequentially with the same position value.
    # Position represents the current stream position for address
    # calculations.
    #
    # @param data [String] Binary data to encode
    # @param position [Integer] Current stream position
    # @return [String] Encoded binary data
    def encode(data, position = 0)
      return data.dup if @filters.empty?

      result = data
      @filters.each do |filter|
        result = filter.encode(result, position)
      end

      result
    end

    # Decode (postprocess) data by applying all filters in reverse order.
    #
    # Filters are applied in reverse order with the same position value
    # to undo the encoding transformation.
    #
    # @param data [String] Binary data to decode
    # @param position [Integer] Current stream position
    # @return [String] Decoded binary data
    def decode(data, position = 0)
      return data.dup if @filters.empty?

      result = data
      # Apply filters in reverse order
      @filters.reverse_each do |filter|
        result = filter.decode(result, position)
      end

      result
    end

    # Clear all filters from the pipeline.
    #
    # @return [void]
    def clear
      @filters.clear
      @position = 0
    end
  end
end
