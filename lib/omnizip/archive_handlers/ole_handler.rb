# frozen_string: true

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for OLE compound documents ( MSI installers,
    # legacy Office binaries): stream listing, reading, and
    # extraction. Stream names are listed exactly as stored — MSI
    # installers mangle their table-stream names in a
    # MSI-domain encoding this handler does not decode.
    class OleHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "compound documents cannot be created through the " \
              "convenience API; use Omnizip::Formats::Ole directly"
      end

      def extract_to(path, output_dir, **_)
        Omnizip::Formats::Ole.extract(path, output_dir)
        Dir.glob(File.join(output_dir, "**", "*"))
          .select { |f| File.file?(f) }
      end

      def list(path, details: false, **_)
        entries = Omnizip::Formats::Ole.list(path)
        return entries unless details

        entries.map { |name| { name: name, size: nil, directory: false } }
      end

      def read_entry(path, entry_name, **_)
        Omnizip::Formats::Ole.read(path, entry_name)
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:ole, Omnizip::ArchiveHandlers::OleHandler.new)
