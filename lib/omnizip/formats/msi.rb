# frozen_string_literal: true

require "omnizip/formats/ole"
require "omnizip/formats/msi/constants"

module Omnizip
  module Formats
    # MSI (Microsoft Installer) format support
    #
    # Provides read access to MSI packages, extracting files from
    # embedded or external cabinet archives.
    #
    # MSI files are OLE compound documents containing:
    # - Database tables (File, Component, Directory, Media, etc.)
    # - String pool for interned strings
    # - Embedded cabinets (in _Streams or direct OLE streams)
    module Msi
      autoload :Entry, "omnizip/formats/msi/entry"
      autoload :StringPool, "omnizip/formats/msi/string_pool"
      autoload :TableParser, "omnizip/formats/msi/table_parser"
      autoload :DirectoryResolver, "omnizip/formats/msi/directory_resolver"
      autoload :CabExtractor, "omnizip/formats/msi/cab_extractor"
      autoload :Reader, "omnizip/formats/msi/reader"

      class << self
        # Open MSI file and return reader
        #
        # @param path [String] Path to MSI file
        # @yield [Reader] Reader instance
        # @return [Reader]
        def open(path)
          reader = Reader.new(path)
          reader.open
          if block_given?
            begin
              yield reader
            ensure
              reader.close
            end
          else
            reader
          end
        end

        # List files in MSI package
        #
        # @param path [String] Path to MSI file
        # @return [Array<String>] File paths
        def list(path)
          open(path) { |r| r.files.map(&:path) }
        end

        # Extract all files from MSI package
        #
        # @param path [String] Path to MSI file
        # @param output_dir [String] Output directory
        # @return [Array<String>] Extracted file paths
        def extract(path, output_dir)
          open(path) do |reader|
            reader.extract(output_dir)
            reader.files.map { |f| File.join(output_dir, f.path) }
          end
        end

        # Get information about MSI package
        #
        # @param path [String] Path to MSI file
        # @return [Hash] Package information
        def info(path)
          open(path, &:info)
        end

        # Register MSI format with format registry
        #
        # This overrides OLE's .msi registration.
        def register!
          require "omnizip/format_registry"
          FormatRegistry.register(".msi", self)
          FormatRegistry.register(".msp", self)
        end
      end
    end
  end
end

# Auto-register MSI format (overrides OLE's .msi registration)
Omnizip::Formats::Msi.register!
