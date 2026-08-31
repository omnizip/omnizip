# frozen_string_literal: true

require "tmpdir"

module Omnizip
  module ArchiveHandlers
    # Read-only adapter for the RAR format. RAR compression is
    # patented software (see link:README[RAR write support]); this
    # handler exposes extraction/listing/reading only, so the
    # convenience API and the Archive facade can operate on existing
    # archives truthfully instead of raising on every operation.
    class RarHandler
      def create(_path, **_options)
        raise Omnizip::UnsupportedFormatError,
              "RAR archives cannot be created (patented format); " \
              "Omnizip reads RAR archives only"
      end

      def extract_to(path, output_dir, password: nil, **_)
        Omnizip::Formats::Rar::Decompressor.extract(path, output_dir,
                                                    password: password)
        reader = Omnizip::Formats::Rar::Reader.new(path).open
        reader.list_files.reject(&:is_dir)
          .map { |e| ::File.join(output_dir, e.name) }
      end

      def list(path, details: false, **_)
        reader = Omnizip::Formats::Rar::Reader.new(path).open
        entries = reader.list_files
        if details
          entries.map do |e|
            { name: e.name, size: e.size, directory: e.is_dir,
              compressed_size: (e.compressed_size if e.compressed_size.positive?),
              mtime: e.mtime }
          end
        else
          entries.map(&:name)
        end
      end

      def read_entry(path, entry_name, password: nil, **_)
        Dir.mktmpdir("omnizip-rar-entry") do |dir|
          dest = File.join(dir, "entry")
          Omnizip::Formats::Rar::Decompressor.extract_entry(
            path, entry_name, dest, password: password
          )
          File.binread(dest)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:rar, Omnizip::ArchiveHandlers::RarHandler.new)
