# frozen_string_literal: true

require "tmpdir"

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for the ISO 9660 format (disk images).
    # Extraction and listing are supported; ISO writing exists at the
    # format level but is not exposed through the convenience archive
    # API.
    class IsoHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "iso images cannot be created through the convenience " \
              "API; use Omnizip::Formats::Iso.create directly"
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Iso.extract(path, output_dir)
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Iso.list(path)
        if details
          entries.map do |e|
            { name: e.full_path, size: e.size, directory: e.directory?,
              mtime: e.recording_date }
          end
        else
          entries.map(&:full_path)
        end
      end

      def read_entry(path, entry_name, **_)
        entry = Omnizip::Formats::Iso.list(path)
          .find { |e| e.full_path == entry_name }
        unless entry
          raise Errno::ENOENT, "Entry not found: #{entry_name}"
        end
        raise Errno::EISDIR, "Entry is a directory: #{entry_name}" if entry.directory?

        Dir.mktmpdir("omnizip-iso-entry") do |dir|
          dest = File.join(dir, "entry")
          Omnizip::Formats::Iso.open(path) do |iso|
            iso.extract_entry(entry_name, dest)
          end
          File.binread(dest)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:iso, Omnizip::ArchiveHandlers::IsoHandler.new)
