# frozen_string_literal: true

module Omnizip
  module ArchiveHandlers
    # Adapter that exposes the canonical +create+/+open+/+extract_to+
    # /+list+ interface for the ZIP format on the native
    # +Formats::Zip+ tree. In-place entry editing (+add_entry+ /
    # +remove_entry+) still goes through the rubyzip-compat
    # +Omnizip::Zip::File+ layer: it is an in-place central-directory
    # rewriter the native tree does not have (the same reason the
    # Metadata subsystem lives there).
    class ZipHandler
      def create(path, compression_method: nil, level: nil, **_, &block)
        writer = Formats::Zip::Writer.new(path)
        block&.call(WriterProxy.new(writer))

        # The native writer takes archive-level compression at #write
        # time; keep profile keywords out of it
        kwargs = {}
        kwargs[:compression_method] = compression_method if compression_method
        kwargs[:level] = level if level
        writer.write(**kwargs)
        path
      end

      def open(path, &block)
        reader = Formats::Zip::Reader.new(path)
        block ? yield(reader) : reader
      end

      def extract_to(path, output_dir, overwrite: false, **_)
        reader = Formats::Zip::Reader.new(path)

        if overwrite
          reader.extract_all(output_dir)
          reader.entries.map { |e| ::File.join(output_dir, e.filename) }
        else
          extracted = []
          reader.entries.each do |entry|
            dest_path = ::File.join(output_dir, entry.filename)
            raise Errno::EEXIST, "File exists: #{dest_path}" if ::File.exist?(dest_path)

            reader.extract_entry(entry, output_dir)
            extracted << dest_path
          end
          extracted
        end
      end

      def list(path, details: false, **_)
        reader = Formats::Zip::Reader.new(path)
        return reader.entries.map(&:filename) unless details

        reader.entries.map do |entry|
          {
            name: entry.filename,
            size: entry.uncompressed_size,
            compressed_size: entry.compressed_size,
            compression_method: entry.compression_method,
            crc: entry.crc32,
            time: entry.time,
            directory: entry.directory?,
          }
        end
      end

      def read_entry(path, entry_name)
        Formats::Zip::Reader.new(path).read_entry(entry_name)
      end

      def add_entry(path, entry_name, source_path)
        Omnizip::Zip::File.open(path) { |zip| zip.add(entry_name, source_path) }
      end

      def remove_entry(path, entry_name)
        Omnizip::Zip::File.open(path) { |zip| zip.remove(entry_name) }
      end

      # Translates the generic +add(name, source_path)+ and
      # +add_data(name, data)+ interface onto the native writer
      class WriterProxy
        def initialize(writer)
          @writer = writer
        end

        def add(name, source_path = nil, &block)
          if source_path
            @writer.add_file(source_path, name)
          elsif block
            @writer.add_data(name, yield)
          else
            @writer.add_directory(name)
          end
        end

        def add_data(name, data)
          @writer.add_data(name, data)
        end
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:zip, Omnizip::ArchiveHandlers::ZipHandler.new)
