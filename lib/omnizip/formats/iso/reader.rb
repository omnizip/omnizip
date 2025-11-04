# frozen_string_literal: true

require_relative "volume_descriptor"
require_relative "directory_record"
require_relative "path_table"
require "fileutils"

module Omnizip
  module Formats
    module Iso
      # ISO 9660 image reader
      # Provides read-only access to ISO filesystem
      class Reader
        attr_reader :file_path, :primary_volume_descriptor, :entries,
                    :path_table

        # Initialize reader
        #
        # @param file_path [String] Path to ISO file
        def initialize(file_path)
          @file_path = file_path
          @primary_volume_descriptor = nil
          @entries = []
          @path_table = nil
          @io = nil
        end

        # Open and parse ISO image
        #
        # @raise [RuntimeError] if file cannot be opened or is invalid
        def open
          @io = File.open(@file_path, "rb")
          parse_volume_descriptors
          parse_directory_structure
          self
        end

        # Close ISO file
        def close
          @io&.close
          @io = nil
        end

        # Get volume identifier
        #
        # @return [String] Volume name
        def volume_identifier
          @primary_volume_descriptor&.volume_identifier || ""
        end

        # Get system identifier
        #
        # @return [String] System identifier
        def system_identifier
          @primary_volume_descriptor&.system_identifier || ""
        end

        # Get volume size in bytes
        #
        # @return [Integer] Total volume size
        def volume_size
          return 0 unless @primary_volume_descriptor

          @primary_volume_descriptor.volume_space_size * Iso::SECTOR_SIZE
        end

        # Extract entry to file
        #
        # @param entry_path [String] Path in ISO
        # @param output_path [String] Destination path
        def extract_entry(entry_path, output_path)
          entry = find_entry(entry_path)
          raise "Entry not found: #{entry_path}" unless entry

          if entry.directory?
            FileUtils.mkdir_p(output_path)
          else
            FileUtils.mkdir_p(File.dirname(output_path))
            data = read_file_data(entry)
            File.binwrite(output_path, data)

            # Set modification time if available
            File.utime(entry.mtime, entry.mtime, output_path) if entry.mtime
          end
        end

        # Extract all entries
        #
        # @param output_dir [String] Output directory
        def extract_all(output_dir)
          FileUtils.mkdir_p(output_dir)

          @entries.each do |entry|
            next if entry.current_directory? || entry.parent_directory?

            output_path = File.join(output_dir, entry.name)
            extract_entry(entry.name, output_path)
          end
        end

        # List all entries
        #
        # @return [Array<DirectoryRecord>] All entries
        def list_files
          @entries.reject { |e| e.current_directory? || e.parent_directory? }
        end

        private

        # Parse volume descriptors
        def parse_volume_descriptors
          sector = Iso::VOLUME_DESCRIPTOR_START

          loop do
            @io.seek(sector * Iso::SECTOR_SIZE)
            data = @io.read(Iso::SECTOR_SIZE)
            raise "Failed to read volume descriptor" unless data

            vd = VolumeDescriptor.parse(data)

            case vd.type
            when Iso::VD_PRIMARY
              @primary_volume_descriptor = vd
            when Iso::VD_TERMINATOR
              break
            end

            sector += 1
          end

          return if @primary_volume_descriptor

          raise "No primary volume descriptor found"
        end

        # Parse directory structure
        def parse_directory_structure
          return unless @primary_volume_descriptor

          root = @primary_volume_descriptor.root_directory_record
          parse_directory(root, "")
        end

        # Recursively parse directory
        #
        # @param dir_record [DirectoryRecord] Directory record
        # @param path_prefix [String] Path prefix
        def parse_directory(dir_record, path_prefix)
          # Read directory data
          @io.seek(dir_record.location * Iso::SECTOR_SIZE)
          dir_data = @io.read(dir_record.data_length)

          offset = 0
          while offset < dir_data.bytesize
            length = dir_data.getbyte(offset)
            break if length.zero? # End of directory

            record = DirectoryRecord.parse(dir_data, offset)

            # Skip current and parent directory entries
            unless record.current_directory? || record.parent_directory?
              # Set full path
              full_path = path_prefix.empty? ? record.name : "#{path_prefix}/#{record.name}"
              record.instance_variable_set(:@full_path, full_path)

              @entries << record

              # Recursively parse subdirectories
              parse_directory(record, full_path) if record.directory?
            end

            offset += length
          end
        end

        # Find entry by path
        #
        # @param path [String] Entry path
        # @return [DirectoryRecord, nil] Found entry
        def find_entry(path)
          # Normalize path
          path = path.gsub(%r{^/+}, "").gsub(%r{/+$}, "")
          @entries.find { |e| e.instance_variable_get(:@full_path) == path }
        end

        # Read file data
        #
        # @param entry [DirectoryRecord] File entry
        # @return [String] File data
        def read_file_data(entry)
          @io.seek(entry.location * Iso::SECTOR_SIZE)
          @io.read(entry.size)
        end
      end
    end
  end
end
