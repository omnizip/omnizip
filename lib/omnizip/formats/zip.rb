# frozen_string_literal: true

require_relative "zip/constants"
require_relative "zip/local_file_header"
require_relative "zip/central_directory_header"
require_relative "zip/end_of_central_directory"
require_relative "zip/reader"
require_relative "zip/writer"

module Omnizip
  module Formats
    # ZIP archive format implementation
    module Zip
      class << self
        # Read a ZIP archive
        def read(file_path)
          Reader.new(file_path).read
        end

        # Create a ZIP archive
        def create(file_path, &block)
          writer = Writer.new(file_path)
          block.call(writer) if block_given?
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
          require_relative "../format_registry"
          FormatRegistry.register(".zip", Omnizip::Formats::Zip)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Zip.register!