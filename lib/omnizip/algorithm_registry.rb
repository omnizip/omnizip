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
  # Registry for managing compression algorithm classes.
  #
  # This class provides a centralized registry for compression algorithms,
  # allowing algorithms to self-register and be retrieved by name.
  # It implements a plugin-style architecture for extensibility.
  class AlgorithmRegistry
    class << self
      # Register an algorithm class with the registry.
      #
      # @param name [Symbol, String] The name identifier for the algorithm
      # @param klass [Class] The algorithm class to register
      # @raise [ArgumentError] If name or klass is nil
      # @return [void]
      def register(name, klass)
        raise ArgumentError, "Algorithm name cannot be nil" if name.nil?
        raise ArgumentError, "Algorithm class cannot be nil" if klass.nil?

        algorithms[name.to_sym] = klass
      end

      # Retrieve an algorithm class by name.
      #
      # @param name [Symbol, String] The name identifier for the algorithm
      # @raise [UnknownAlgorithmError] If algorithm is not registered
      # @return [Class] The registered algorithm class
      def get(name)
        algorithm = algorithms[name.to_sym]
        return algorithm if algorithm

        raise UnknownAlgorithmError,
              "Unknown algorithm: #{name}. " \
              "Available: #{available.join(', ')}"
      end

      # Check if an algorithm is registered.
      #
      # @param name [Symbol, String] The name identifier for the algorithm
      # @return [Boolean] True if algorithm is registered, false otherwise
      def registered?(name)
        algorithms.key?(name.to_sym)
      end

      # Get list of all registered algorithm names.
      #
      # @return [Array<Symbol>] Array of registered algorithm names
      def available
        algorithms.keys
      end

      # Reset the registry (primarily for testing).
      #
      # @return [void]
      def reset!
        algorithms.clear
      end

      private

      # Get or initialize the algorithms hash.
      #
      # @return [Hash] The algorithms registry
      def algorithms
        @algorithms ||= {}
      end
    end
  end
end
