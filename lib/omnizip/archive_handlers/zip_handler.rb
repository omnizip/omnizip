# frozen_string_literal: true

module Omnizip
  module ArchiveHandlers
    # Adapter that exposes the canonical +create+/+open+/+extract_to+
    # /+list+ interface for the ZIP format. Wraps +Omnizip::Zip::File+.
    class ZipHandler
      def create(path, &block)
        Omnizip::Zip::File.create(path, &block)
      end

      def open(path, &block)
        Omnizip::Zip::File.open(path, &block)
      end

      def extract_to(path, output_dir, overwrite: false, **_)
        extracted = []
        Omnizip::Zip::File.open(path) do |zip|
          zip.each do |entry|
            dest_path = ::File.join(output_dir, entry.name)
            on_exists = if overwrite
                          proc { true }
                        else
                          proc { |_e, p| raise "File exists: #{p}" }
                        end
            zip.extract(entry, dest_path, &on_exists)
            extracted << dest_path
          end
        end
        extracted
      end

      def list(path, details: false, **_)
        Omnizip::Zip::File.open(path) do |zip|
          if details
            zip.entries.map do |entry|
              {
                name: entry.name,
                size: entry.size,
                compressed_size: entry.compressed_size,
                compression_method: entry.compression_method,
                crc: entry.crc,
                time: entry.time,
                directory: entry.directory?,
              }
            end
          else
            zip.names
          end
        end
      end

      def read_entry(path, entry_name)
        Omnizip::Zip::File.open(path) do |zip|
          entry = zip.get_entry(entry_name)
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

          zip.read(entry)
        end
      end

      def add_entry(path, entry_name, source_path)
        Omnizip::Zip::File.open(path) { |zip| zip.add(entry_name, source_path) }
      end

      def remove_entry(path, entry_name)
        Omnizip::Zip::File.open(path) { |zip| zip.remove(entry_name) }
      end
    end
  end
end

Omnizip::ArchiveHandler.register(:zip, Omnizip::ArchiveHandlers::ZipHandler.new)
