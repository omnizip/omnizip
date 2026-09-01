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

require "lutaml/model"

module Omnizip
  module Models
    # Configuration model for a filter in a compression pipeline.
    #
    # This class replaces hash-based filter configuration with a proper
    # model class. It provides format-aware ID resolution and validation.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    #
    # @example Create a BCJ filter configuration
    #   config = FilterConfig.new(name: :bcj_x86, architecture: :x86)
    #   config.id_for_format(:xz)         # => 0x04
    #   config.id_for_format(:seven_zip)  # => 0x03030103
    #
    # @example Create a Delta filter configuration
    #   config = FilterConfig.new(name: :delta)
    #   config.delta?  # => true
    class FilterConfig < Lutaml::Model::Serializable
      attribute :name, :symbol
      attribute :properties, :string, default: ""
      attribute :architecture, :symbol

      key_value do
        map "name", to: :name, render_default: true, render_nil: true
        map "properties", to: :properties,
                          render_default: true, render_nil: true
        map "architecture", to: :architecture,
                            render_default: true, render_nil: true
      end

      # Initialize filter configuration. The legacy +name_sym+ key is
      # accepted as an alias for +name+.
      #
      # @param attributes [Hash] Initialization attributes
      # @option attributes [Symbol] :name Filter name
      # @option attributes [Symbol] :name_sym Filter name (alias)
      # @option attributes [String] :properties Binary properties data
      # @option attributes [Symbol] :architecture Target architecture
      def initialize(attributes = {})
        attrs = attributes.dup
        attrs[:name] ||= attrs.delete(:name_sym)
        attrs[:properties] ||= "" # empty-string defaults do not render
        super(attrs)
      end

      # Get filter name as symbol (legacy alias for #name).
      #
      # @return [Symbol] Filter name
      def name_sym
        name
      end

      # Get filter instance from registry.
      #
      # @return [Object] Filter instance from FilterRegistry
      # @raise [KeyError] If filter not found in registry
      def filter_instance
        filter = Omnizip::FilterRegistry.get(name)

        # Handle architecture parameter if needed
        if architecture && requires_initialize_kwargs?(filter)
          filter.new(architecture: architecture)
        else
          filter.new
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
        # FilterRegistry accepts any class, with no inheritance check.
        # allowed: keeps NotImplementedError for filters without the method
        if filter.respond_to?(:id_for_format)
          filter.id_for_format(format)
        else
          raise NotImplementedError,
                "Filter #{name} doesn't support format-aware IDs. " \
                "Use the newer BCJ filter instead."
        end
      end

      # Check if this is a BCJ filter.
      #
      # @return [Boolean] True if BCJ filter variant
      def bcj?
        name.to_s.start_with?("bcj_")
      end

      # Check if this is a Delta filter.
      #
      # @return [Boolean] True if Delta filter
      def delta?
        name == :delta
      end

      # Validate configuration.
      #
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If filter name is nil or not registered
      def validate!
        raise ArgumentError, "Filter name is required" if name.nil?

        unless Omnizip::FilterRegistry.registered?(name)
          raise ArgumentError, "Filter not registered: #{name}"
        end

        true
      end

      private

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
