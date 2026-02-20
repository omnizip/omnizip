# frozen_string_literal: true

require_relative "ole/constants"
require_relative "ole/header"
require_relative "ole/allocation_table"
require_relative "ole/dirent"
require_relative "ole/ranges_io"
require_relative "ole/storage"
require_relative "ole/types/variant"

module Omnizip
  module Formats
    # OLE compound document format support
    #
    # Provides read access to Microsoft OLE compound documents,
    # commonly used for .doc, .xls, .ppt files and MSI installers.
    #
    # @example Open OLE file and list contents
    #   Omnizip::Formats::Ole.open('document.doc') do |ole|
    #     ole.list('/').each { |name| puts name }
    #   end
    #
    # @example Read a stream from OLE file
    #   Omnizip::Formats::Ole.open('document.doc') do |ole|
    #     data = ole.read('/WordDocument')
    #   end
    module Ole
      class << self
        # Open OLE file
        #
        # @param path [String] Path to OLE file
        # @yield [Storage] Storage object
        # @return [Storage]
        def open(path)
          storage = Storage.open(path)
          if block_given?
            begin
              yield storage
            ensure
              storage.close
            end
          else
            storage
          end
        end

        # List entries in OLE file
        #
        # @param path [String] Path to OLE file
        # @param dir_path [String] Directory path within OLE (default: "/")
        # @return [Array<String>] Entry names
        def list(path, dir_path = "/")
          self.open(path) { |ole| ole.list(dir_path) }
        end

        # Read stream from OLE file
        #
        # @param ole_path [String] Path to OLE file
        # @param stream_path [String] Path to stream within OLE
        # @return [String] Stream content
        def read(ole_path, stream_path)
          self.open(ole_path) { |ole| ole.read(stream_path) }
        end

        # Get info about entry in OLE file
        #
        # @param ole_path [String] Path to OLE file
        # @param entry_path [String] Path to entry within OLE
        # @return [Hash, nil] Entry info
        def info(ole_path, entry_path = "/")
          self.open(ole_path) { |ole| ole.info(entry_path) }
        end

        # Check if entry exists in OLE file
        #
        # @param ole_path [String] Path to OLE file
        # @param entry_path [String] Path to entry within OLE
        # @return [Boolean]
        def exist?(ole_path, entry_path)
          self.open(ole_path) { |ole| ole.exist?(entry_path) }
        end

        # Check if entry is a file (stream)
        #
        # @param ole_path [String] Path to OLE file
        # @param entry_path [String] Path to entry within OLE
        # @return [Boolean]
        def file?(ole_path, entry_path)
          self.open(ole_path) { |ole| ole.file?(entry_path) }
        end

        # Check if entry is a directory (storage)
        #
        # @param ole_path [String] Path to OLE file
        # @param entry_path [String] Path to entry within OLE
        # @return [Boolean]
        def directory?(ole_path, entry_path)
          self.open(ole_path) { |ole| ole.directory?(entry_path) }
        end

        # Extract all streams to directory
        #
        # @param ole_path [String] Path to OLE file
        # @param output_dir [String] Output directory
        def extract(ole_path, output_dir)
          self.open(ole_path) do |ole|
            extract_dirent(ole.root, output_dir, ole)
          end
        end

        # Register OLE format in registry
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".ole", Storage)
          FormatRegistry.register(".doc", Storage)
          FormatRegistry.register(".xls", Storage)
          FormatRegistry.register(".ppt", Storage)
          FormatRegistry.register(".msi", Storage)
        end

        private

        # Recursively extract dirent to directory
        def extract_dirent(dirent, output_path, ole)
          FileUtils.mkdir_p(output_path)

          dirent.children.each do |child|
            child_path = File.join(output_path, child.name)

            if child.file?
              # Write file content
              File.binwrite(child_path, child.read)
            else
              # Recurse into directory
              extract_dirent(child, child_path, ole)
            end
          end
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Ole.register!
