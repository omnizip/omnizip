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

require_relative "algorithm_registry"

module Omnizip
  # Abstract base class for compression algorithms.
  #
  # All compression algorithms should inherit from this class and implement
  # the required methods. Algorithms are automatically registered with the
  # AlgorithmRegistry when defined.
  class Algorithm
    attr_reader :options, :filter

    # Initialize algorithm with options.
    #
    # @param options [Hash] Algorithm-specific options
    def initialize(options = {})
      @options = options
      @filter = nil
    end

    # Set a preprocessing filter for this algorithm.
    #
    # The filter will be applied before compression and reversed after
    # decompression. Returns self for method chaining.
    #
    # @param filter [Filters::FilterBase, FilterPipeline] Filter or
    #   pipeline to use
    # @return [self] For method chaining
    def with_filter(filter)
      @filter = filter
      self
    end

    # Compress data from input to output.
    #
    # If a filter is set, data is filtered before compression.
    #
    # @param input [IO, String, #read] Input source
    # @param output [IO, #write] Output destination
    # @raise [NotImplementedError] Must be implemented by subclass
    # @return [void]
    def compress(input, output)
      raise NotImplementedError,
            "#{self.class} must implement #compress"
    end

    # Decompress data from input to output.
    #
    # If a filter is set, data is unfiltered after decompression.
    #
    # @param input [IO, String, #read] Input source
    # @param output [IO, #write] Output destination
    # @raise [NotImplementedError] Must be implemented by subclass
    # @return [void]
    def decompress(input, output)
      raise NotImplementedError,
            "#{self.class} must implement #decompress"
    end

    class << self
      # Get metadata about this algorithm.
      #
      # @raise [NotImplementedError] Must be implemented by subclass
      # @return [Models::AlgorithmMetadata] Algorithm metadata
      def metadata
        raise NotImplementedError,
              "#{self} must implement .metadata"
      end

      # Automatically register algorithm when inherited.
      #
      # This hook is called whenever a class inherits from Algorithm,
      # automatically registering it with the AlgorithmRegistry.
      #
      # @param subclass [Class] The inheriting class
      # @return [void]
      def inherited(subclass)
        super
        # Register algorithm when metadata is defined
        subclass.define_singleton_method(:register_algorithm) do
          meta = subclass.metadata
          AlgorithmRegistry.register(meta.name.to_sym, subclass)
        rescue NotImplementedError
          # Metadata not yet defined, will be registered manually
        end
      end
    end

    protected

    # Apply filter to data if filter is set.
    #
    # @param data [String] Data to filter
    # @param position [Integer] Stream position
    # @return [String] Filtered data
    def apply_filter(data, position = 0)
      return data unless @filter

      @filter.encode(data, position)
    end

    # Reverse filter on data if filter is set.
    #
    # @param data [String] Data to unfilter
    # @param position [Integer] Stream position
    # @return [String] Unfiltered data
    def reverse_filter(data, position = 0)
      return data unless @filter

      @filter.decode(data, position)
    end
  end
end
