# frozen_string: true

require "tmpdir"

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for the XAR archive format: extraction and
    # listing over the XML TOC. XAR writing exists at the format
    # level but is not exposed through the convenience archive API.
    class XarHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "xar archives cannot be created through the convenience " \
              "API; use Omnizip::Formats::Xar.create directly"
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Xar.extract(path, output_dir)
        Dir.glob(File.join(output_dir, "**", "*"))
          .select { |f| File.file?(f) }
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Xar.list(path)
        if details
          entries.map do |e|
            { name: e.name, size: e.size,
              directory: false }
          end
        else
          entries.map(&:name)
        end
      end

      def read_entry(path, entry_name, **_)
        Dir.mktmpdir("omnizip-xar-entry") do |dir|
          Omnizip::Formats::Xar.extract(path, dir)
          dest = File.join(dir, entry_name)
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless
            File.exist?(dest)

          File.binread(dest)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:xar, Omnizip::ArchiveHandlers::XarHandler.new)
