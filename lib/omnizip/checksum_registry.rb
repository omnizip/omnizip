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
  # Registry for managing available checksum algorithms.
  #
  # This class maintains a central registry of all checksum implementations
  # available in Omnizip, providing a consistent interface for algorithm
  # discovery and instantiation.
  #
  # The registry pattern ensures that checksum algorithms are defined in
  # one place and can be easily extended with new implementations without
  # modifying existing code.
  #
  # @example Register a new checksum algorithm
  #   ChecksumRegistry.register(:crc32, Omnizip::Checksums::Crc32)
  #
  # @example Get a checksum class
  #   crc_class = ChecksumRegistry.get(:crc32)
  #   checksum = crc_class.calculate("data")
  #
  # @example List available checksums
  #   ChecksumRegistry.available
  #   # => [:crc32, :crc64]
  class ChecksumRegistry
    @checksums = {}

    class << self
      # Register a checksum algorithm.
      #
      # Adds a new checksum implementation to the registry, making it
      # available for use throughout the application.
      #
      # @param name [Symbol] unique identifier for the checksum
      # @param checksum_class [Class] class implementing the checksum
      # @return [void]
      # @raise [ArgumentError] if name is already registered
      def register(name, checksum_class)
        name = name.to_sym
        if @checksums.key?(name)
          raise ArgumentError,
                "Checksum '#{name}' is already registered"
        end

        @checksums[name] = checksum_class
      end

      # Retrieve a checksum class by name.
      #
      # Returns the checksum class registered under the given name,
      # allowing for instantiation and use.
      #
      # @param name [Symbol] identifier of the checksum to retrieve
      # @return [Class] the checksum class
      # @raise [UnknownAlgorithmError] if checksum not found
      def get(name)
        name = name.to_sym
        checksum_class = @checksums[name]

        unless checksum_class
          raise UnknownAlgorithmError,
                "Unknown checksum: '#{name}'. Available: " \
                "#{available.join(', ')}"
        end

        checksum_class
      end

      # List all available checksum algorithms.
      #
      # Returns an array of registered checksum names, useful for
      # displaying options to users or validating input.
      #
      # @return [Array<Symbol>] array of registered checksum names
      def available
        @checksums.keys.sort
      end

      # Check if a checksum is registered.
      #
      # @param name [Symbol] identifier of the checksum to check
      # @return [Boolean] true if registered, false otherwise
      def registered?(name)
        @checksums.key?(name.to_sym)
      end

      # Clear all registered checksums.
      #
      # This method is primarily for testing purposes and should not
      # be used in production code.
      #
      # @return [void]
      # @api private
      def clear
        @checksums.clear
      end
    end
  end
end
