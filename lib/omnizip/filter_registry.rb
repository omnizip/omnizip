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
  # Registry for managing filter classes.
  #
  # This class provides a centralized registry for preprocessing filters,
  # allowing filters to self-register and be retrieved by name.
  # It implements a plugin-style architecture for extensibility.
  class FilterRegistry
    @filters = {}

    class << self
      # Register a filter class with format support.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @param filter_class [Class] The filter class to register
      # @param formats [Array<Symbol>] Supported formats (default: [:xz,
      #   :seven_zip])
      # @return [void]
      def register(name, filter_class, formats: %i[xz seven_zip])
        raise ArgumentError, "Filter name cannot be nil" if name.nil?
        raise ArgumentError, "Filter class cannot be nil" if filter_class.nil?

        @filters[name.to_sym] = {
          class: filter_class,
          formats: formats,
        }
      end
      alias register_with_formats register

      # Retrieve a filter class by name.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @raise [UnknownFilterError] If filter is not registered
      # @return [Class] The registered filter class
      def get(name)
        filter = @filters[name.to_sym]
        unless filter
          raise UnknownFilterError,
                "Unknown filter: #{name}. " \
                "Available: #{available.join(', ')}"
        end

        filter[:class]
      end

      # Check if a filter is registered.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @return [Boolean] True if filter is registered, false otherwise
      def registered?(name)
        @filters.key?(name.to_sym)
      end

      # Get list of all registered filter names.
      #
      # @return [Array<Symbol>] Array of registered filter names
      def available
        @filters.keys
      end

      # Reset the registry (primarily for testing).
      #
      # @return [void]
      def reset!
        @filters.clear
      end

      # Get filter instance for specific format.
      #
      # Returns a new filter instance after verifying the filter supports
      # the specified format.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @param format [Symbol] Format identifier (:xz, :seven_zip)
      # @raise [KeyError] If filter is not registered
      # @raise [ArgumentError] If filter doesn't support the format
      # @return [Object] New filter instance
      def get_for_format(name, format)
        filter_info = @filters[name.to_sym]
        raise KeyError, "Filter not found: #{name}" unless filter_info

        unless filter_info[:formats].include?(format)
          raise ArgumentError,
                "Filter #{name} not supported for format #{format}"
        end

        filter_info[:class].new
      end

      # Check if filter supports specific format.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @param format [Symbol] Format identifier
      # @return [Boolean] True if filter supports the format
      def supports_format?(name, format)
        return false unless @filters[name.to_sym]

        filter_info = @filters[name.to_sym]
        filter_info[:formats]&.include?(format)
      end

      # Get all filters supporting a specific format.
      #
      # @param format [Symbol] Format identifier
      # @return [Array<Symbol>] Filter names supporting the format
      def filters_for_format(format)
        @filters.select do |_, info|
          info[:formats]&.include?(format)
        end.keys
      end
    end
  end

  # Error raised when an unknown filter is requested
  class UnknownFilterError < StandardError; end
end
