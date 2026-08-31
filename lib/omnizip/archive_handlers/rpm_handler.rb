# frozen_string: true

require "tmpdir"

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for the RPM package format: extraction and
    # listing over the CPIO payload; package metadata lives in
    # Formats::Rpm.info. RPM writing exists at the format level but
    # is not exposed through the convenience archive API.
    class RpmHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "rpm archives cannot be created through the convenience " \
              "API; use Omnizip::Formats::Rpm::Writer directly"
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Rpm.extract(path, output_dir)
        Dir.glob(File.join(output_dir, "**", "*"))
          .select { |f| File.file?(f) }
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Rpm.list(path)
        return entries unless details

        entries.map { |name| { name: name, size: nil, directory: false } }
      end

      def read_entry(path, entry_name, **_)
        Dir.mktmpdir("omnizip-rpm-entry") do |dir|
          Omnizip::Formats::Rpm.extract(path, dir)
          dest = File.join(dir, entry_name)
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless
            File.exist?(dest)

          File.binread(dest)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:rpm, Omnizip::ArchiveHandlers::RpmHandler.new)
