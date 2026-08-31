# frozen_string_literal: true

module Omnizip
  module ArchiveHandlers
    # Adapter that exposes the canonical +create+/+extract_to+/+list+
    # interface for the 7z format. Wraps +Omnizip::Formats::SevenZip+.
    class SevenZipHandler
      # Creates a .7z archive. The yielded proxy only supports
      # +add(name, source_path)+ for files — directory entries are not
      # part of the single-file convenience flow.
      def create(path, **options, &block)
        Omnizip::Formats::SevenZip.create(path, options) do |writer|
          block&.call(FileProxy.new(writer))
        end
      end

      def extract_to(path, output_dir, **options)
        extracted = []
        Omnizip::Formats::SevenZip.open(path, options) do |reader|
          reader.extract_all(output_dir)
          extracted = reader.list_files.reject(&:is_dir)
            .map { |e| ::File.join(output_dir, e.name) }
        end
        extracted
      end

      def list(path, details: false, **options)
        with_reader(path, options) do |reader|
          entries = reader.list_files
          if details
            entries.map do |e|
              { name: e.name, size: e.size, directory: e.is_dir,
                compressed_size: (e.compressed_size if e.compressed_size&.positive?),
                mtime: e.mtime }
            end
          else
            entries.map(&:name)
          end
        end
      end

      def read_entry(path, entry_name, **options)
        with_reader(path, options) do |reader|
          entry = reader.list_files.find { |e| e.name == entry_name }
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

          reader.extract_entry_data(File.open(path, "rb"), entry)
        end
      end

      private

      # The SevenZip.open facade returns the reader, discarding the
      # block's value — so drive the Reader directly.
      def with_reader(path, options)
        reader = Omnizip::Formats::SevenZip::Reader.new(path, options)
        reader.open
        begin
          yield reader
        ensure
          reader.split_reader&.close
        end
      end

      # Translates the generic +add(name, source_path)+ interface to
      # the 7z writer's +add_file(file_path, archive_path)+.
      class FileProxy
        def initialize(writer)
          @writer = writer
        end

        def add(name, source_path = nil)
          if source_path
            @writer.add_file(source_path, name)
          else
            @writer.add_directory_entry(name)
          end
        end

        def add_data(name, data)
          @writer.add_data(name, data)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:seven_zip,
                                 Omnizip::ArchiveHandlers::SevenZipHandler.new)
