# frozen_string_literal: true

require_relative "tar/constants"
require_relative "tar/entry"
require_relative "tar/header"
require_relative "tar/reader"
require_relative "tar/writer"

module Omnizip
  module Formats
    # TAR archive format implementation
    #
    # TAR (Tape Archive) is a simple archive format that bundles files
    # without compression. It's commonly used in combination with
    # compression formats like GZIP (.tar.gz) or BZIP2 (.tar.bz2).
    #
    # This implementation supports POSIX ustar format with:
    # - Regular files
    # - Directories
    # - Symbolic links
    # - Hard links
    # - Metadata preservation (permissions, timestamps, ownership)
    module Tar
      class << self
        # Read a TAR archive
        #
        # @param file_path [String] Path to TAR archive
        # @return [Reader] TAR reader instance
        def read(file_path)
          Reader.new(file_path).read
        end

        # Open a TAR archive with block syntax
        #
        # @param file_path [String] Path to TAR archive
        # @yield [Reader] TAR reader instance
        # @return [Reader] TAR reader instance
        # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- Ruby 3.0 compatibility
        def open(file_path, &block)
          Reader.open(file_path, &block)
        end
        # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

        # Create a TAR archive
        #
        # @param file_path [String] Path to output TAR archive
        # @yield [Writer] TAR writer instance
        # @return [Writer] TAR writer instance
        # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- Ruby 3.0 compatibility
        def create(file_path, &block)
          Writer.create(file_path, &block)
        end
        # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

        # Extract a TAR archive
        #
        # @param file_path [String] Path to TAR archive
        # @param output_dir [String] Output directory
        def extract(file_path, output_dir)
          reader = read(file_path)
          reader.extract_all(output_dir)
        end

        # List entries in a TAR archive
        #
        # @param file_path [String] Path to TAR archive
        # @return [Array<Entry>] List of entries
        def list(file_path)
          reader = read(file_path)
          reader.list_entries
        end

        # Register TAR format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".tar", Omnizip::Formats::Tar)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Tar.register!
