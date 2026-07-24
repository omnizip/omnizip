# frozen_string_literal: true

module Omnizip
  module ArchiveHandlers
    # Adapter that exposes the canonical +create+/+open+/+extract_to+
    # /+list+ interface for the TAR format. Wraps +Omnizip::Formats::Tar+.
    class TarHandler
      def create(path, &block)
        Omnizip::Formats::Tar.create(path, &block)
      end

      def open(path, &block)
        Omnizip::Formats::Tar.open(path, &block)
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Tar.extract(path, output_dir)
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Tar.list(path)
        if details
          entries.map do |entry|
            {
              name: entry.name,
              size: entry.size,
              directory: entry.directory?,
              mtime: entry.mtime,
              mode: entry.mode,
            }
          end
        else
          entries.map(&:name)
        end
      end

      def read_entry(path, entry_name)
        data = nil
        Omnizip::Formats::Tar.open(path) do |reader|
          entry = reader.entries.find { |e| e.name == entry_name }
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

          data = entry.data
        end
        data
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:tar, Omnizip::ArchiveHandlers::TarHandler.new)
