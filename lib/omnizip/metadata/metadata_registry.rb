# frozen_string_literal: true

module Omnizip
  module Metadata
    # Registry of supported metadata per archive format
    class MetadataRegistry
      @registry = {}

      class << self
        # Register metadata support for a format
        # @param format [Symbol] Format name (e.g., :zip, :seven_zip)
        # @param supported_fields [Array<Symbol>] Supported metadata fields
        def register(format, supported_fields)
          @registry[format] = supported_fields
        end

        # Check if a format supports a metadata field
        # @param format [Symbol] Format name
        # @param field [Symbol] Metadata field name
        # @return [Boolean] True if supported
        def supports?(format, field)
          fields = @registry[format]
          return false unless fields

          fields.include?(field)
        end

        # Get all supported fields for a format
        # @param format [Symbol] Format name
        # @return [Array<Symbol>] List of supported fields
        def supported_fields(format)
          @registry[format] || []
        end

        # Get all registered formats
        # @return [Array<Symbol>] List of formats
        def formats
          @registry.keys
        end

        # Reset registry (for testing)
        def reset
          @registry = {}
        end
      end
    end

    # Register ZIP format metadata support
    MetadataRegistry.register(:zip, %i[
                                comment
                                mtime
                                unix_permissions
                                external_attributes
                                filename
                                extra_field
                              ])

    # Register 7z format metadata support (limited)
    MetadataRegistry.register(:seven_zip, %i[
                                mtime
                                attributes
                              ])
  end
end
