# frozen_string_literal: true

module Omnizip
  module ArchiveHandlers
    # Adapter that exposes the canonical +create+/+extract_to+/+list+
    # interface for the 7z format. Wraps +Omnizip::Formats::SevenZip+.
    class SevenZipHandler
      # Creates a .7z archive. The yielded proxy only supports
      # +add(name, source_path)+ for files — directory entries are not
      # part of the single-file convenience flow.
      def create(path, &block)
        Omnizip::Formats::SevenZip.create(path) do |writer|
          block&.call(FileProxy.new(writer))
        end
      end

      def extract_to(path, output_dir, **options)
        Omnizip::Formats::SevenZip.open(path, options) do |reader|
          reader.extract_all(output_dir)
        end
      end

      def list(path, details: false, **options)
        Omnizip::Formats::SevenZip.open(path, options) do |reader|
          files = reader.list_files
          return details ? files.map { |f| { name: f } } : files
        end
      end

      def read_entry(_path, _entry_name)
        raise NotImplementedError,
              "read_from_archive for .7z is not wired; use " \
              "Formats::SevenZip.open"
      end

      # Translates the generic +add(name, source_path)+ interface to
      # the 7z writer's +add_file(file_path, archive_path)+.
      class FileProxy
        def initialize(writer)
          @writer = writer
        end

        # Directory entries are a no-op: 7z archives derive the
        # directory tree from the files' archive paths ("sub/f.txt"
        # implies "sub/"), and the writer/reader handle slashed
        # paths (verified against 7zz).
        def add(name, source_path = nil)
          return if source_path.nil?

          @writer.add_file(source_path, name)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:seven_zip,
                                 Omnizip::ArchiveHandlers::SevenZipHandler.new)
