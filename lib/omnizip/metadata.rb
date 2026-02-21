# frozen_string_literal: true

module Omnizip
  # Metadata editing module
  # Provides in-place metadata modification without recompression
  module Metadata
    autoload :EntryMetadata, "omnizip/metadata/entry_metadata"
    autoload :ArchiveMetadata, "omnizip/metadata/archive_metadata"
    autoload :MetadataValidator, "omnizip/metadata/metadata_validator"
    autoload :MetadataRegistry, "omnizip/metadata/metadata_registry"
    autoload :MetadataEditor, "omnizip/metadata/metadata_editor"

    class << self
      # Edit entry metadata
      # @param entry [Omnizip::Zip::Entry] Entry to edit
      # @yield [metadata] Block to modify metadata
      # @return [EntryMetadata] Entry metadata object
      def edit_entry(entry, &block)
        metadata = EntryMetadata.new(entry)
        yield(metadata) if block
        metadata
      end

      # Edit archive metadata
      # @param archive [Omnizip::Zip::File] Archive to edit
      # @yield [metadata] Block to modify metadata
      # @return [ArchiveMetadata] Archive metadata object
      def edit_archive(archive, &block)
        metadata = ArchiveMetadata.new(archive)
        yield(metadata) if block
        metadata
      end

      # Create a metadata editor for batch operations
      # @param archive [Omnizip::Zip::File] Archive to edit
      # @return [MetadataEditor] Metadata editor
      def editor(archive)
        MetadataEditor.new(archive)
      end

      # Validate metadata
      # @param metadata [EntryMetadata, ArchiveMetadata] Metadata to validate
      # @return [Boolean] True if valid
      def validate(metadata)
        validator = MetadataValidator.new
        case metadata
        when EntryMetadata
          validator.validate_entry(metadata)
        when ArchiveMetadata
          validator.validate_archive(metadata)
        else
          raise ArgumentError, "Unknown metadata type: #{metadata.class}"
        end
      end
    end
  end
end
