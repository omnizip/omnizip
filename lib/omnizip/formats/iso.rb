# frozen_string_literal: true

require_relative "iso/reader"
require_relative "iso/writer"
require_relative "iso/volume_descriptor"
require_relative "iso/volume_builder"
require_relative "iso/directory_record"
require_relative "iso/directory_builder"
require_relative "iso/path_table"
require_relative "iso/rock_ridge"
require_relative "iso/joliet"

module Omnizip
  module Formats
    # ISO 9660 CD-ROM filesystem format support
    # Provides read-only access to ISO images
    #
    # ISO 9660 is the standard filesystem for CD-ROMs and DVD-ROMs.
    # This implementation supports:
    # - Primary Volume Descriptor parsing
    # - Directory structure traversal
    # - File extraction
    # - Rock Ridge extensions (basic)
    module Iso
      # ISO 9660 constants
      SECTOR_SIZE = 2048
      SYSTEM_AREA_SECTORS = 16
      VOLUME_DESCRIPTOR_START = SYSTEM_AREA_SECTORS

      # Volume descriptor types
      VD_BOOT_RECORD = 0
      VD_PRIMARY = 1
      VD_SUPPLEMENTARY = 2
      VD_PARTITION = 3
      VD_TERMINATOR = 255

      # File flags
      FLAG_HIDDEN = 0x01
      FLAG_DIRECTORY = 0x02
      FLAG_ASSOCIATED = 0x04
      FLAG_EXTENDED = 0x08
      FLAG_PERMISSIONS = 0x10
      FLAG_NOT_FINAL = 0x80

      # Open existing ISO image
      #
      # @param path [String] Path to ISO file
      # @yield [reader] Block for reading archive
      # @yieldparam reader [Reader] ISO reader
      # @return [Reader] ISO reader
      def self.open(path)
        reader = Reader.new(path)
        reader.open

        if block_given?
          begin
            yield reader
          ensure
            reader.close
          end
        end

        reader
      end

      # List contents of ISO image
      #
      # @param path [String] Path to ISO file
      # @return [Array<DirectoryRecord>] Directory entries
      def self.list(path)
        open(path, &:entries)
      end

      # Extract ISO contents
      #
      # @param iso_path [String] Path to ISO file
      # @param output_dir [String] Output directory
      def self.extract(iso_path, output_dir)
        open(iso_path) do |iso|
          iso.extract_all(output_dir)
        end
      end

      # Get ISO volume information
      #
      # @param path [String] Path to ISO file
      # @return [Hash] Volume information
      def self.info(path)
        open(path) do |iso|
          {
            format: "ISO 9660",
            volume_id: iso.volume_identifier,
            system_id: iso.system_identifier,
            size: iso.volume_size,
            files: iso.entries.count { |e| !e.directory? },
            directories: iso.entries.count(&:directory?)
          }
        end
      end

      # Create ISO 9660 image
      #
      # @param path [String] Output ISO file path
      # @param options [Hash] Creation options
      # @yield [writer] Block for adding files/directories
      # @yieldparam writer [Writer] ISO writer
      # @return [String] Path to created ISO
      #
      # @example Create ISO image
      #   Omnizip::Formats::Iso.create('backup.iso') do |iso|
      #     iso.volume_id = 'BACKUP_2024'
      #     iso.add_directory('documents/')
      #   end
      #
      # @example With Rock Ridge and Joliet
      #   Omnizip::Formats::Iso.create('cdrom.iso',
      #     rock_ridge: true,
      #     joliet: true
      #   ) do |iso|
      #     iso.add_directory('files/')
      #   end
      def self.create(path, options = {})
        writer = Writer.new(path, options)

        yield writer if block_given?

        writer.write
      end

      # Auto-register ISO format when loaded
      def self.register!
        require_relative "../format_registry"
        FormatRegistry.register(".iso", Reader)
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Iso.register!
