# frozen_string_literal: true

require "tmpdir"

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for the CPIO format (initramfs images, RPM
    # payloads). Extraction and listing are supported; CPIO writing
    # exists at the format level but is not exposed through the
    # convenience archive API.
    class CpioHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "cpio archives cannot be created through the convenience " \
              "API; use Omnizip::Formats::Cpio.create directly"
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Cpio.extract(path, output_dir)
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Cpio.list(path)
        if details
          entries.map do |e|
            { name: e.name, size: e.data.bytesize,
              directory: e.name.end_with?("/"), mtime: nil }
          end
        else
          entries.map(&:name)
        end
      end

      def read_entry(path, entry_name, **_)
        entry = Omnizip::Formats::Cpio.list(path)
          .find { |e| e.name == entry_name }
        unless entry
          raise Errno::ENOENT, "Entry not found: #{entry_name}"
        end

        entry.data
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:cpio, Omnizip::ArchiveHandlers::CpioHandler.new)
