# frozen_string_literal: true

require "tmpdir"
require "tempfile"

module Omnizip
  module ArchiveHandlers
    # Adapter for the RAR format: extraction/listing/reading, plus
    # creation through Formats::Rar (RAR5 STORE is unrar-verified;
    # compressed methods fall back to STORE with a warning — see the
    # README interop table).
    class RarHandler
      def create(path, **options, &block)
        proxy = nil
        result = Omnizip::Formats::Rar.create(path, options) do |writer|
          proxy = WriterProxy.new(writer)
          block&.call(proxy)
        end
        proxy&.cleanup
        result
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

      # Translates the generic +add(name, source_path)+ /
      # +add_data(name, data)+ / +add_directory(name)+ interface onto
      # the RAR writers. The writers take file paths, so in-memory
      # content spills to a temporary file.
      class WriterProxy
        def initialize(writer)
          @writer = writer
          @spill = []
        end

        def add(name, source_path = nil)
          if source_path
            @writer.add_file(source_path, name)
          else
            @writer.add_directory_entry(name)
          end
        end

        def add_data(name, data)
          file = Tempfile.new(["omnizip_rar_entry", File.extname(name)])
          file.binmode
          file.write(data)
          file.close
          @spill << file
          @writer.add_file(file.path, name)
        end

        def add_directory(name)
          @writer.add_directory_entry(name)
        end

        # Remove the temporary files add_data spilled
        def cleanup
          @spill.each(&:unlink)
          @spill.clear
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:rar, Omnizip::ArchiveHandlers::RarHandler.new)
