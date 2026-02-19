# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
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

require_relative "filter_config"

module Omnizip
  module Models
    # Ordered sequence of filters for compression/decompression
    #
    # Manages a pipeline of filters that are applied in sequence.
    # Filters are applied in reverse order during decode.
    #
    # @example Create filter chain for XZ executable
    #   chain = FilterChain.new(format: :xz)
    #   chain.add_filter(name: :"bcj-x86", architecture: :x86)
    #   chain.add_filter(name: :lzma2)  # Main compression
    #   encoded = chain.encode_all(data, position)
    class FilterChain
      # @return [Array<FilterConfig>] Ordered filter configurations
      attr_reader :filters

      # @return [Symbol] Format identifier (:xz, :seven_zip)
      attr_reader :format

      # Maximum filters in XZ format
      MAX_FILTERS_XZ = 4

      # Maximum filters in 7z format
      MAX_FILTERS_SEVEN_ZIP = 4

      # Initialize filter chain
      #
      # @param attributes [Hash] Initialization attributes
      # @option attributes [Symbol] :format Target format
      def initialize(attributes = {})
        @format = attributes[:format] || :xz
        @filters = attributes[:filters] || []
      end

      # Add a filter to the chain
      #
      # @param filter_attributes [Hash] Filter configuration
      # @option filter_attributes [Symbol] :name Filter name
      # @option filter_attributes [String] :properties Filter properties
      # @option filter_attributes [Symbol] :architecture Target architecture
      # @return [self] For chaining
      def add_filter(filter_attributes = {})
        filter = FilterConfig.new(filter_attributes)
        filter.validate!
        @filters << filter
        self
      end

      # Get maximum filters for current format
      #
      # @return [Integer] Maximum number of filters allowed
      def max_filters
        case @format
        when :xz then MAX_FILTERS_XZ
        when :seven_zip then MAX_FILTERS_SEVEN_ZIP
        else raise ArgumentError, "Unknown format: #{@format}"
        end
      end

      # Validate filter chain
      #
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If validation fails
      def validate!
        if @filters.size > max_filters
          raise ArgumentError,
                "Too many filters for #{@format}: #{@filters.size} > #{max_filters}"
        end

        @filters.each(&:validate!)
        true
      end

      # Encode data through all filters in order
      #
      # @param data [String] Input data
      # @param position [Integer] Stream position
      # @return [String] Encoded data
      def encode_all(data, position = 0)
        result = data
        @filters.each do |filter_config|
          filter = filter_config.filter_instance
          result = filter.encode(result, position)
        end
        result
      end

      # Decode data through all filters in reverse order
      #
      # @param data [String] Input data
      # @param position [Integer] Stream position
      # @return [String] Decoded data
      def decode_all(data, position = 0)
        result = data
        @filters.reverse_each do |filter_config|
          filter = filter_config.filter_instance
          result = filter.decode(result, position)
        end
        result
      end

      # Get filter IDs for current format
      #
      # @return [Array<Integer>] Array of filter IDs in order
      def filter_ids
        @filters.map { |f| f.id_for_format(@format) }
      end

      # Check if chain is empty
      #
      # @return [Boolean] True if no filters
      def empty?
        @filters.empty?
      end

      # Get number of filters in chain
      #
      # @return [Integer] Filter count
      def size
        @filters.size
      end
    end
  end
end
