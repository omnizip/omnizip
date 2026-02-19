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

require_relative "../filter_registry"

module Omnizip
  module Models
    # Configuration model for a filter in a compression pipeline.
    #
    # This class replaces hash-based filter configuration with a proper
    # model class. It provides format-aware ID resolution and validation.
    #
    # @example Create a BCJ filter configuration
    #   config = FilterConfig.new(name: :bcj_x86, architecture: :x86)
    #   config.id_for_format(:xz)         # => 0x04
    #   config.id_for_format(:seven_zip)  # => 0x03030103
    #
    # @example Create a Delta filter configuration
    #   config = FilterConfig.new(name: :delta)
    #   config.delta?  # => true
    class FilterConfig
      # @return [Symbol] Filter name (:bcj_x86, :delta, etc.)
      attr_reader :name_sym

      # @return [String] Binary properties data for filter configuration
      attr_accessor :properties

      # @return [Symbol] Target architecture for BCJ filters
      attr_accessor :architecture

      # Initialize filter configuration.
      #
      # @param attributes [Hash] Initialization attributes
      # @option attributes [Symbol] :name Filter name
      # @option attributes [Symbol] :name_sym Filter name (alternative key)
      # @option attributes [String] :properties Binary properties data
      # @option attributes [Symbol] :architecture Target architecture
      def initialize(attributes = {})
        @name_sym = attributes[:name] || attributes[:name_sym]
        @properties = attributes[:properties] || "".b
        @architecture = attributes[:architecture]
      end

      # Set filter name.
      #
      # @param value [Symbol] Filter name
      # @return [void]
      def name=(value)
        @name_sym = value
      end

      # Get filter name as symbol.
      #
      # @return [Symbol] Filter name
      def name_sym
        @name_sym
      end

      # Get filter instance from registry.
      #
      # Returns a new instance of the filter. Handles both old-style
      # registration (direct class) and new-style registration (hash with :class).
      #
      # @return [Object] Filter instance from FilterRegistry
      # @raise [KeyError] If filter not found in registry
      def filter_instance
        filter = Omnizip::FilterRegistry.get(@name_sym)

        # Handle both hash-style and direct class registration
        if filter.is_a?(Hash)
          # New-style registration - check if architecture is needed
          klass = filter[:class]
          if architecture_required?(klass)
            klass.new(architecture: @architecture) if @architecture
          else
            klass.new
          end
        elsif filter.is_a?(Class)
          # Old-style registration - try with architecture if available
          if @architecture && requires_initialize_kwargs?(filter)
            filter.new(architecture: @architecture)
          else
            filter.new
          end
        else
          # Already an instance
          filter
        end
      end

      # Get filter ID for specific format.
      #
      # Delegates to filter instance's id_for_format method if available.
      # For older filters without id_for_format, returns a default value.
      #
      # @param format [Symbol] Format identifier (:seven_zip, :xz)
      # @return [Integer] Format-specific filter ID
      # @raise [NotImplementedError] If filter doesn't support id_for_format
      def id_for_format(format)
        filter = filter_instance
        if filter.respond_to?(:id_for_format)
          filter.id_for_format(format)
        else
          raise NotImplementedError,
                "Filter #{@name_sym} doesn't support format-aware IDs. " \
                "Use the newer BCJ filter instead."
        end
      end

      # Check if this is a BCJ filter.
      #
      # @return [Boolean] True if BCJ filter variant
      def bcj?
        @name_sym.to_s.start_with?("bcj_")
      end

      # Check if this is a Delta filter.
      #
      # @return [Boolean] True if Delta filter
      def delta?
        @name_sym == :delta
      end

      # Validate configuration.
      #
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If filter name is nil or not registered
      def validate!
        raise ArgumentError, "Filter name is required" if @name_sym.nil?

        unless Omnizip::FilterRegistry.registered?(@name_sym)
          raise ArgumentError, "Filter not registered: #{@name_sym}"
        end

        true
      end

      # Convert to hash for backward compatibility.
      #
      # @return [Hash] Hash representation with :name, :properties, :architecture
      def to_h
        {
          name: @name_sym,
          properties: @properties,
          architecture: @architecture,
        }
      end

      private

      # Check if filter class requires architecture argument.
      #
      # @param klass [Class] Filter class to check
      # @return [Boolean] True if architecture is required
      def architecture_required?(klass)
        klass.name.include?("BCJ") && !klass.name.include?("BcjX86")
      end

      # Check if filter class requires keyword arguments for initialize.
      #
      # @param klass [Class] Filter class to check
      # @return [Boolean] True if kwargs are required
      def requires_initialize_kwargs?(klass)
        klass.name.include?("BCJ") && !klass.name.include?("BcjX86")
      end
    end
  end
end
