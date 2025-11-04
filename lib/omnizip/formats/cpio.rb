# frozen_string_literal: true

require_relative "cpio/constants"
require_relative "cpio/entry"
require_relative "cpio/writer"
require_relative "cpio/reader"

module Omnizip
  module Formats
    # CPIO archive format support
    #
    # Provides read and write access to CPIO archives in multiple formats:
    # - newc (SVR4 new ASCII format) - Most common, used in initramfs
    # - CRC (newc with CRC checksums)
    # - ODC (Old portable ASCII format)
    #
    # CPIO is commonly used for:
    # - Linux initramfs/initrd
    # - RPM package contents
    # - Unix system backups
    #
    # @example Create CPIO archive
    #   Omnizip::Formats::Cpio.create('archive.cpio') do |cpio|
    #     cpio.add_directory('files/')
    #   end
    #
    # @example Extract CPIO archive
    #   Omnizip::Formats::Cpio.extract('archive.cpio', 'output/')
    module Cpio
      class << self
        # Create CPIO archive
        #
        # @param path [String] Output CPIO file path
        # @param format [Symbol] CPIO format (:newc, :crc, :odc)
        # @yield [writer] Block for adding files/directories
        # @yieldparam writer [Writer] CPIO writer
        # @return [String] Path to created archive
        #
        # @example Create newc format archive
        #   Omnizip::Formats::Cpio.create('archive.cpio') do |cpio|
        #     cpio.add_file('kernel.img')
        #     cpio.add_directory('modules/')
        #   end
        #
        # @example Create with CRC checksums
        #   Omnizip::Formats::Cpio.create('archive.cpio', format: :crc) do |cpio|
        #     cpio.add_directory('initramfs/')
        #   end
        def create(path, format: :newc)
          writer = Writer.new(path, format: format)

          yield writer if block_given?

          writer.write
        end

        # Open CPIO archive for reading
        #
        # @param path [String] Path to CPIO file
        # @yield [reader] Block for reading archive
        # @yieldparam reader [Reader] CPIO reader
        # @return [Reader] CPIO reader
        #
        # @example Read CPIO archive
        #   Omnizip::Formats::Cpio.open('archive.cpio') do |cpio|
        #     cpio.entries.each { |entry| puts entry.name }
        #   end
        def open(path)
          reader = Reader.new(path)
          reader.open

          if block_given?
            yield reader
          else
            reader
          end
        end

        # List CPIO archive contents
        #
        # @param path [String] Path to CPIO file
        # @return [Array<Entry>] Archive entries
        #
        # @example List archive contents
        #   entries = Omnizip::Formats::Cpio.list('archive.cpio')
        #   entries.each { |e| puts "#{e.name} (#{e.filesize} bytes)" }
        def list(path)
          open(path, &:list)
        end

        # Extract CPIO archive
        #
        # @param cpio_path [String] Path to CPIO file
        # @param output_dir [String] Output directory
        #
        # @example Extract archive
        #   Omnizip::Formats::Cpio.extract('archive.cpio', 'output/')
        def extract(cpio_path, output_dir)
          open(cpio_path) do |cpio|
            cpio.extract_all(output_dir)
          end
        end

        # Get archive information
        #
        # @param path [String] Path to CPIO file
        # @return [Hash] Archive information
        #
        # @example Get archive info
        #   info = Omnizip::Formats::Cpio.info('archive.cpio')
        #   puts "Format: #{info[:format]}"
        #   puts "Files: #{info[:file_count]}"
        def info(path)
          open(path) do |cpio|
            entries = cpio.list

            {
              format: cpio.format_name,
              format_type: cpio.format,
              entry_count: entries.size,
              file_count: entries.count(&:file?),
              directory_count: entries.count(&:directory?),
              symlink_count: entries.count(&:symlink?),
              total_size: entries.sum(&:filesize)
            }
          end
        end

        # Auto-register CPIO format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".cpio", Reader)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Cpio.register!