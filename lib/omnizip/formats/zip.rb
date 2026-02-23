# frozen_string_literal: true

module Omnizip
  module Formats
    # ZIP archive format implementation
    module Zip
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/formats/zip/constants"
      autoload :LocalFileHeader, "omnizip/formats/zip/local_file_header"
      autoload :CentralDirectoryHeader, "omnizip/formats/zip/central_directory_header"
      autoload :EndOfCentralDirectory, "omnizip/formats/zip/end_of_central_directory"
      autoload :Zip64EndOfCentralDirectory, "omnizip/formats/zip/zip64_end_of_central_directory"
      autoload :Zip64EndOfCentralDirectoryLocator, "omnizip/formats/zip/zip64_end_of_central_directory_locator"
      autoload :Zip64ExtraField, "omnizip/formats/zip/zip64_extra_field"
      autoload :Reader, "omnizip/formats/zip/reader"
      autoload :Writer, "omnizip/formats/zip/writer"
      autoload :UnixExtraField, "omnizip/formats/zip/unix_extra_field"

      class << self
        # Read a ZIP archive
        def read(file_path)
          Reader.new(file_path).read
        end

        # Create a ZIP archive
        def create(file_path, &block)
          writer = Writer.new(file_path)
          yield(writer) if block
          writer
        end

        # Extract a ZIP archive
        def extract(file_path, output_dir)
          reader = read(file_path)
          reader.extract_all(output_dir)
        end

        # List entries in a ZIP archive
        def list(file_path)
          reader = read(file_path)
          reader.list_entries
        end

        # Auto-register .zip format when loaded
        def register!
          require "omnizip/format_registry"
          FormatRegistry.register(".zip", Omnizip::Formats::Zip)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Zip.register!
