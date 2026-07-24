# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # Registry for RAR compression methods
      #
      # This class manages the registration and retrieval of compression
      # methods for RAR archives. It follows the Registry pattern to allow
      # dynamic addition of compression methods without modifying core code.
      #
      # @example Registering a compression method
      #   CompressionMethodRegistry.register(
      #     :rar3_normal,
      #     Rar3::Compressor,
      #     Rar3::Decompressor
      #   )
      #
      # @example Getting a compressor
      #   compressor = CompressionMethodRegistry.compressor(:rar3_normal)
      class CompressionMethodRegistry
        class << self
          # Register a compression method
          #
          # @param name [Symbol] The method name
          # @param compressor [Class] The compressor class
          # @param decompressor [Class] The decompressor class
          # @return [void]
          def register(name, compressor, decompressor)
            methods[name] = {
              compressor: compressor,
              decompressor: decompressor,
            }
          end

          # Get a compressor for a method
          #
          # @param name [Symbol] The method name
          # @return [Class] The compressor class
          # @raise [Error::FormatError] If method not registered
          def compressor(name)
            method_data = methods[name]
            return method_data[:compressor] if method_data

            raise Error::FormatError,
                  "No compressor registered for method: #{name}"
          end

          # Get a decompressor for a method
          #
          # @param name [Symbol] The method name
          # @return [Class] The decompressor class
          # @raise [Error::FormatError] If method not registered
          def decompressor(name)
            method_data = methods[name]
            return method_data[:decompressor] if method_data

            raise Error::FormatError,
                  "No decompressor registered for method: #{name}"
          end

          # Check if a method is registered
          #
          # @param name [Symbol] The method name
          # @return [Boolean] True if registered
          def registered?(name)
            methods.key?(name)
          end

          # Get all registered method names
          #
          # @return [Array<Symbol>] The registered method names
          def registered_methods
            methods.keys
          end

          # Clear all registered methods (primarily for testing)
          #
          # @return [void]
          def clear
            @methods = {}
          end

          # Get a compression method for a RAR version and level
          #
          # @param version [String] The RAR version (e.g., "3.0", "5.0")
          # @param level [Symbol] The compression level
          # @return [Symbol] The method name
          def method_for_version(version, level)
            prefix = version.start_with?("5") ? "rar5" : "rar3"
            :"#{prefix}_#{level}"
          end

          private

          # Storage for registered methods
          #
          # @return [Hash] The methods hash
          def methods
            @methods ||= {}
          end
        end
      end
    end
  end
end
