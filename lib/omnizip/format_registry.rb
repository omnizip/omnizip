# frozen_string_literal: true

module Omnizip
  # Registry for archive format handlers
  # Manages different archive format readers (7z, zip, tar, etc.)
  class FormatRegistry
    class << self
      # Register a format handler
      #
      # @param extension [String] File extension (e.g., ".7z", ".zip")
      # @param handler_class [Class, String] Format handler class or class name string
      def register(extension, handler_class)
        registry[normalize_extension(extension)] = handler_class
      end

      # Get format handler for extension
      #
      # @param extension [String] File extension
      # @return [Class, Module, nil] Handler class/module or nil if not found
      def get(extension)
        handler = registry[normalize_extension(extension)]
        return handler if handler.nil? || handler.is_a?(Class) || handler.is_a?(Module)

        # Resolve string to class if needed
        resolve_constant(handler)
      end

      # Resolve a string to a constant (class/module)
      #
      # @param name [String] Fully qualified class name
      # @return [Class, Module, nil] Resolved constant or nil
      def resolve_constant(name)
        return nil unless name.is_a?(String)

        names = name.split("::")
        names.shift if names.empty? || names.first.empty?

        constant = Object
        names.each do |n|
          return nil unless constant.const_defined?(n, false)
          constant = constant.const_get(n)
        end
        constant
      rescue StandardError
        nil
      end

      # Check if format is supported
      #
      # @param extension [String] File extension
      # @return [Boolean] true if supported
      def supported?(extension)
        registry.key?(normalize_extension(extension))
      end

      # List all supported formats
      #
      # @return [Array<String>] Supported extensions
      def supported_formats
        registry.keys.sort
      end

      private

      # Format registry storage
      #
      # @return [Hash] Extension to handler class mapping
      def registry
        @registry ||= {}
      end

      # Normalize file extension
      #
      # @param ext [String] Extension
      # @return [String] Normalized extension
      def normalize_extension(ext)
        ext = ext.to_s
        ext = ".#{ext}" unless ext.start_with?(".")
        ext.downcase
      end
    end
  end
end
