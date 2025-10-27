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
      # Register a filter class with the registry.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @param klass [Class] The filter class to register
      # @raise [ArgumentError] If name or klass is nil
      # @return [void]
      def register(name, klass)
        raise ArgumentError, "Filter name cannot be nil" if name.nil?
        raise ArgumentError, "Filter class cannot be nil" if klass.nil?

        @filters[name.to_sym] = klass
      end

      # Retrieve a filter class by name.
      #
      # @param name [Symbol, String] The name identifier for the filter
      # @raise [UnknownFilterError] If filter is not registered
      # @return [Class] The registered filter class
      def get(name)
        filter = @filters[name.to_sym]
        return filter if filter

        raise UnknownFilterError,
              "Unknown filter: #{name}. " \
              "Available: #{available.join(", ")}"
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
    end
  end

  # Error raised when an unknown filter is requested
  class UnknownFilterError < Error; end
end
