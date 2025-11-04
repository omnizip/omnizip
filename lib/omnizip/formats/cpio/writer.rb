# frozen_string_literal: true

require "fileutils"
require_relative "constants"
require_relative "entry"

module Omnizip
  module Formats
    module Cpio
      # CPIO archive writer
      #
      # Creates CPIO archives in newc, CRC, or ODC format.
      # Ported from libarchive's archive_write_set_format_cpio_newc.c
      #
      # @example Create CPIO archive
      #   writer = Cpio::Writer.new('archive.cpio')
      #   writer.add_file('file.txt')
      #   writer.add_directory('dir/')
      #   writer.write
      #
      # @example With CRC format
      #   writer = Cpio::Writer.new('archive.cpio', format: :crc)
      #   writer.add_directory('initramfs/')
      #   writer.write
      class Writer
        include Constants

        # @return [String] Output archive path
        attr_reader :output_path

        # @return [Symbol] CPIO format (:newc, :crc, :odc)
        attr_reader :format

        # @return [Array<Entry>] Entries to write
        attr_reader :entries

        # Initialize CPIO writer
        #
        # @param output_path [String] Output CPIO file path
        # @param format [Symbol] CPIO format (:newc, :crc, :odc)
        def initialize(output_path, format: :newc)
          @output_path = output_path
          @format = validate_format(format)
          @entries = []
          @inode_counter = 1
        end

        # Add file to archive
        #
        # @param file_path [String] Source file path
        # @param cpio_path [String, nil] Path in archive (defaults to file_path)
        # @raise [ArgumentError] if file doesn't exist
        def add_file(file_path, cpio_path = nil)
          raise ArgumentError, "File not found: #{file_path}" unless
            File.exist?(file_path)

          cpio_path ||= file_path
          stat = File.stat(file_path)

          # Read file data unless it's a symlink
          data = if File.symlink?(file_path)
                   File.readlink(file_path)
                 elsif stat.file?
                   File.binread(file_path)
                 else
                   ""
                 end

          entry = create_entry_from_stat(cpio_path, stat, data)
          @entries << entry
          @inode_counter += 1
        end

        # Add directory to archive
        #
        # @param dir_path [String] Source directory path
        # @param recursive [Boolean] Include subdirectories
        # @param cpio_path [String, nil] Path in archive
        # @raise [ArgumentError] if directory doesn't exist
        def add_directory(dir_path, recursive: true, cpio_path: nil)
          raise ArgumentError, "Directory not found: #{dir_path}" unless
            Dir.exist?(dir_path)

          cpio_path ||= dir_path
          stat = File.stat(dir_path)

          # Add directory entry
          entry = create_entry_from_stat(cpio_path, stat, "")
          @entries << entry
          @inode_counter += 1

          # Add contents if recursive
          if recursive
            Dir.foreach(dir_path) do |item|
              next if item == "." || item == ".."

              item_path = File.join(dir_path, item)
              item_cpio_path = "#{cpio_path}/#{item}"

              if File.directory?(item_path)
                add_directory(item_path, recursive: true, cpio_path: item_cpio_path)
              else
                add_file(item_path, item_cpio_path)
              end
            end
          end
        end

        # Write CPIO archive
        #
        # @raise [IOError] if write fails
        def write
          File.open(@output_path, "wb") do |io|
            # Write all entries
            @entries.each do |entry|
              write_entry(io, entry)
            end

            # Write trailer
            write_trailer(io)
          end

          @output_path
        end

        private

        # Validate format
        #
        # @param format [Symbol] Format to validate
        # @return [Symbol] Validated format
        # @raise [ArgumentError] if format invalid
        def validate_format(format)
          unless [:newc, :crc, :odc].include?(format)
            raise ArgumentError, "Invalid CPIO format: #{format}. " \
                                 "Must be :newc, :crc, or :odc"
          end
          format
        end

        # Create entry from file stat
        #
        # @param path [String] Entry path
        # @param stat [File::Stat] File statistics
        # @param data [String] File data
        # @return [Entry] Created entry
        def create_entry_from_stat(path, stat, data)
          Entry.new(
            magic: format_magic,
            ino: @inode_counter,
            mode: stat.mode,
            uid: stat.uid,
            gid: stat.gid,
            nlink: stat.nlink,
            mtime: stat.mtime.to_i,
            filesize: data.bytesize,
            dev_major: (stat.dev >> 8) & 0xFF,
            dev_minor: stat.dev & 0xFF,
            rdev_major: stat.rdev ? (stat.rdev >> 8) & 0xFF : 0,
            rdev_minor: stat.rdev ? (stat.rdev & 0xFF) : 0,
            namesize: path.bytesize + 1,
            checksum: @format == :crc ? calculate_checksum(data) : 0,
            name: path,
            data: data
          )
        end

        # Get magic number for current format
        #
        # @return [String] Magic number
        def format_magic
          case @format
          when :newc then MAGIC_NEWC
          when :crc then MAGIC_CRC
          when :odc then MAGIC_ODC
          end
        end

        # Write entry to archive
        #
        # @param io [IO] Output stream
        # @param entry [Entry] Entry to write
        def write_entry(io, entry)
          binary_data = entry.to_binary(format: @format)
          io.write(binary_data)
        end

        # Write trailer entry
        #
        # @param io [IO] Output stream
        def write_trailer(io)
          trailer = Entry.new(
            magic: format_magic,
            ino: 0,
            mode: 0,
            uid: 0,
            gid: 0,
            nlink: 1,
            mtime: 0,
            filesize: 0,
            dev_major: 0,
            dev_minor: 0,
            rdev_major: 0,
            rdev_minor: 0,
            namesize: TRAILER_NAME.bytesize + 1,
            checksum: 0,
            name: TRAILER_NAME,
            data: ""
          )

          write_entry(io, trailer)
        end

        # Calculate checksum for CRC format
        #
        # @param data [String] Data to checksum
        # @return [Integer] CRC32 checksum
        def calculate_checksum(data)
          require "zlib"
          Zlib.crc32(data) & 0xFFFFFFFF
        end
      end
    end
  end
end