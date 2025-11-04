# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "volume_builder"
require_relative "directory_builder"
require_relative "../iso"

module Omnizip
  module Formats
    module Iso
      # ISO 9660 image writer
      #
      # Creates ISO 9660 filesystem images (CD/DVD images) from files and directories.
      # Supports ISO 9660 levels 1-3, Rock Ridge, and Joliet extensions.
      #
      # @example Create simple ISO image
      #   writer = Iso::Writer.new('cdrom.iso')
      #   writer.add_directory('files/')
      #   writer.write
      #
      # @example With Rock Ridge and Joliet
      #   writer = Iso::Writer.new('backup.iso',
      #     volume_id: 'BACKUP_2024',
      #     rock_ridge: true,
      #     joliet: true
      #   )
      #   writer.add_directory('documents/')
      #   writer.write
      class Writer
        # @return [String] Output ISO file path
        attr_reader :output_path

        # @return [Hash] Writer options
        attr_reader :options

        # @return [String] Volume identifier (label)
        attr_accessor :volume_id

        # @return [String] System identifier
        attr_accessor :system_id

        # @return [String] Publisher
        attr_accessor :publisher

        # @return [String] Preparer
        attr_accessor :preparer

        # @return [String] Application identifier
        attr_accessor :application

        # @return [Integer] ISO 9660 level (1, 2, or 3)
        attr_accessor :level

        # @return [Boolean] Use Rock Ridge extensions
        attr_accessor :rock_ridge

        # @return [Boolean] Use Joliet extensions
        attr_accessor :joliet

        # @return [Array<Hash>] Files to add
        attr_reader :files

        # @return [Array<Hash>] Directories to add
        attr_reader :directories

        # Initialize ISO writer
        #
        # @param output_path [String] Output ISO file path
        # @param options [Hash] Writer options
        # @option options [String] :volume_id Volume label
        # @option options [String] :system_id System identifier
        # @option options [String] :publisher Publisher name
        # @option options [String] :preparer Preparer name
        # @option options [String] :application Application name
        # @option options [Integer] :level ISO 9660 level (1-3)
        # @option options [Boolean] :rock_ridge Enable Rock Ridge
        # @option options [Boolean] :joliet Enable Joliet
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = default_options.merge(options)

          @volume_id = @options[:volume_id]
          @system_id = @options[:system_id]
          @publisher = @options[:publisher]
          @preparer = @options[:preparer]
          @application = @options[:application]
          @level = @options[:level]
          @rock_ridge = @options[:rock_ridge]
          @joliet = @options[:joliet]

          @files = []
          @directories = []
        end

        # Add file to ISO image
        #
        # @param file_path [String] Source file path
        # @param iso_path [String, nil] Path in ISO (defaults to basename)
        # @raise [ArgumentError] if file doesn't exist
        def add_file(file_path, iso_path = nil)
          raise ArgumentError, "File not found: #{file_path}" unless
            File.exist?(file_path)

          iso_path ||= File.basename(file_path)

          @files << {
            source: File.expand_path(file_path),
            iso_path: sanitize_path(iso_path),
            stat: File.stat(file_path)
          }
        end

        # Add directory to ISO image
        #
        # @param dir_path [String] Source directory path
        # @param recursive [Boolean] Include subdirectories
        # @param iso_path [String, nil] Path in ISO (defaults to basename)
        # @raise [ArgumentError] if directory doesn't exist
        def add_directory(dir_path, recursive: true, iso_path: nil)
          raise ArgumentError, "Directory not found: #{dir_path}" unless
            Dir.exist?(dir_path)

          iso_path ||= File.basename(dir_path)
          iso_path = sanitize_path(iso_path)

          if recursive
            add_directory_recursive(dir_path, iso_path)
          else
            add_directory_flat(dir_path, iso_path)
          end
        end

        # Create ISO image
        #
        # @raise [IOError] if write fails
        def write
          File.open(@output_path, "wb") do |io|
            # Build directory structure
            builder = DirectoryBuilder.new(
              @files,
              @directories,
              level: @level,
              rock_ridge: @rock_ridge
            )
            dir_structure = builder.build

            # Build volume descriptor
            volume_builder = VolumeBuilder.new(
              volume_id: @volume_id,
              system_id: @system_id,
              publisher: @publisher,
              preparer: @preparer,
              application: @application,
              level: @level,
              rock_ridge: @rock_ridge,
              joliet: @joliet
            )

            # Write ISO structure
            write_system_area(io)
            write_volume_descriptors(io, volume_builder, dir_structure)
            write_path_tables(io, dir_structure)
            write_directories(io, dir_structure)
            write_file_data(io)
          end

          @output_path
        end

        private

        # Default writer options
        #
        # @return [Hash] Default options
        def default_options
          {
            volume_id: "OMNIZIP_ISO",
            system_id: "LINUX",
            publisher: "OMNIZIP",
            preparer: "OMNIZIP #{Omnizip::VERSION}",
            application: "OMNIZIP",
            level: 2,
            rock_ridge: true,
            joliet: true
          }
        end

        # Add directory recursively
        #
        # @param dir_path [String] Source directory
        # @param iso_path [String] ISO path
        def add_directory_recursive(dir_path, iso_path)
          # Add directory itself
          @directories << {
            source: File.expand_path(dir_path),
            iso_path: iso_path,
            stat: File.stat(dir_path)
          }

          # Add all contents
          Dir.foreach(dir_path) do |entry|
            next if entry == "." || entry == ".."

            source_path = File.join(dir_path, entry)
            target_path = "#{iso_path}/#{entry}"

            if File.directory?(source_path)
              add_directory_recursive(source_path, target_path)
            else
              add_file(source_path, target_path)
            end
          end
        end

        # Add directory flat (non-recursive)
        #
        # @param dir_path [String] Source directory
        # @param iso_path [String] ISO path
        def add_directory_flat(dir_path, iso_path)
          @directories << {
            source: File.expand_path(dir_path),
            iso_path: iso_path,
            stat: File.stat(dir_path)
          }

          Dir.foreach(dir_path) do |entry|
            next if entry == "." || entry == ".."

            source_path = File.join(dir_path, entry)
            next if File.directory?(source_path)

            add_file(source_path, "#{iso_path}/#{entry}")
          end
        end

        # Sanitize path for ISO filesystem
        #
        # @param path [String] Input path
        # @return [String] Sanitized path
        def sanitize_path(path)
          # Remove leading/trailing slashes
          path = path.gsub(%r{^/+}, "").gsub(%r{/+$}, "")

          # Normalize separators
          path.split("/").map { |component| sanitize_filename(component) }.join("/")
        end

        # Sanitize filename for ISO level
        #
        # @param name [String] Filename
        # @return [String] Sanitized filename
        def sanitize_filename(name)
          case @level
          when 1
            # Level 1: 8.3 format, A-Z 0-9 _ only
            base = name.upcase.gsub(/[^A-Z0-9_]/, "_")[0, 8]
            ext = ""
            if name.include?(".")
              ext = "." + name.split(".").last.upcase.gsub(/[^A-Z0-9]/, "")[0, 3]
            end
            base + ext
          when 2
            # Level 2: Up to 31 chars, more relaxed
            name.gsub(/[^A-Za-z0-9_.-]/, "_")[0, 31]
          else
            # Level 3: No restrictions
            name
          end
        end

        # Write system area (first 16 sectors)
        #
        # @param io [IO] Output IO
        def write_system_area(io)
          # System area is reserved, write zeros
          io.write("\x00" * (Iso::SECTOR_SIZE * Iso::SYSTEM_AREA_SECTORS))
        end

        # Write volume descriptors
        #
        # @param io [IO] Output IO
        # @param builder [VolumeBuilder] Volume builder
        # @param dir_structure [Hash] Directory structure
        def write_volume_descriptors(io, builder, dir_structure)
          # Write primary volume descriptor
          pvd = builder.build_primary(dir_structure[:root])
          io.write(pvd)

          # Write Joliet supplementary descriptor if enabled
          if @joliet
            svd = builder.build_joliet(dir_structure[:root])
            io.write(svd)
          end

          # Write terminator
          terminator = build_terminator
          io.write(terminator)
        end

        # Build volume descriptor set terminator
        #
        # @return [String] Terminator sector (2048 bytes)
        def build_terminator
          sector = String.new
          sector << [Iso::VD_TERMINATOR].pack("C")  # Type
          sector << VolumeDescriptor::ISO_IDENTIFIER # "CD001"
          sector << [1].pack("C")                    # Version
          sector << ("\x00" * (Iso::SECTOR_SIZE - 7))
          sector
        end

        # Write path tables
        #
        # @param io [IO] Output IO
        # @param dir_structure [Hash] Directory structure
        def write_path_tables(io, dir_structure)
          # Path tables provide quick directory lookup
          # For simplicity, we'll write minimal path tables

          # Little-endian path table
          path_table = build_path_table(dir_structure[:directories])
          io.write(path_table)

          # Pad to sector boundary
          padding = Iso::SECTOR_SIZE - (path_table.bytesize % Iso::SECTOR_SIZE)
          io.write("\x00" * padding) if padding < Iso::SECTOR_SIZE

          # Big-endian path table (required by spec)
          path_table_be = build_path_table(dir_structure[:directories], big_endian: true)
          io.write(path_table_be)

          # Pad to sector boundary
          padding = Iso::SECTOR_SIZE - (path_table_be.bytesize % Iso::SECTOR_SIZE)
          io.write("\x00" * padding) if padding < Iso::SECTOR_SIZE
        end

        # Build path table
        #
        # @param directories [Array<Hash>] Directory list
        # @param big_endian [Boolean] Use big-endian format
        # @return [String] Path table data
        def build_path_table(directories, big_endian: false)
          table = String.new

          directories.each_with_index do |dir, idx|
            name = dir[:name]
            parent = dir[:parent_idx] || 1

            # Name length
            table << [name.bytesize].pack("C")

            # Extended attribute record length
            table << [0].pack("C")

            # Location of extent
            pack_format = big_endian ? "N" : "V"
            table << [dir[:location]].pack(pack_format)

            # Parent directory number (1-based)
            pack_format = big_endian ? "n" : "v"
            table << [parent + 1].pack(pack_format)

            # Directory name
            table << name

            # Pad to even length
            table << "\x00" if name.bytesize.odd?
          end

          table
        end

        # Write directory records
        #
        # @param io [IO] Output IO
        # @param dir_structure [Hash] Directory structure
        def write_directories(io, dir_structure)
          dir_structure[:directories].each do |dir_info|
            write_directory_record(io, dir_info)
          end
        end

        # Write single directory record
        #
        # @param io [IO] Output IO
        # @param dir_info [Hash] Directory information
        def write_directory_record(io, dir_info)
          # Seek to directory location
          io.seek(dir_info[:location] * Iso::SECTOR_SIZE)

          # Write directory entries
          dir_data = build_directory_data(dir_info)
          io.write(dir_data)

          # Pad to sector boundary
          padding = Iso::SECTOR_SIZE - (dir_data.bytesize % Iso::SECTOR_SIZE)
          io.write("\x00" * padding) if padding < Iso::SECTOR_SIZE
        end

        # Build directory data with all entries
        #
        # @param dir_info [Hash] Directory information
        # @return [String] Directory record data
        def build_directory_data(dir_info)
          data = String.new

          # Add "." entry (current directory)
          data << build_directory_entry("\x00", dir_info, is_self: true)

          # Add ".." entry (parent directory)
          parent = dir_info[:parent] || dir_info
          data << build_directory_entry("\x01", parent, is_self: false)

          # Add child entries
          dir_info[:children].each do |child|
            name = child[:name]
            data << build_directory_entry(name, child, is_self: false)
          end

          data
        end

        # Build single directory entry
        #
        # @param name [String] Entry name
        # @param entry_info [Hash] Entry information
        # @param is_self [Boolean] Is this the "." entry
        # @return [String] Directory entry record
        def build_directory_entry(name, entry_info, is_self:)
          record = String.new

          # Extended attribute length (0)
          ext_attr_len = 0

          # Calculate record length
          name_len = name.bytesize
          padding = name_len.even? ? 1 : 0
          record_len = 33 + name_len + padding

          # Byte 0: Length of directory record
          record << [record_len].pack("C")

          # Byte 1: Extended attribute record length
          record << [ext_attr_len].pack("C")

          # Bytes 2-9: Location of extent (both-endian)
          location = entry_info[:location] || 0
          record << [location].pack("V") # Little-endian
          record << [location].pack("N") # Big-endian

          # Bytes 10-17: Data length (both-endian)
          data_length = entry_info[:size] || 0
          record << [data_length].pack("V")
          record << [data_length].pack("N")

          # Bytes 18-24: Recording date and time
          record << encode_record_datetime(entry_info[:mtime] || Time.now)

          # Byte 25: File flags
          flags = 0
          flags |= Iso::FLAG_DIRECTORY if entry_info[:directory]
          record << [flags].pack("C")

          # Byte 26: File unit size (0 for non-interleaved)
          record << [0].pack("C")

          # Byte 27: Interleave gap size
          record << [0].pack("C")

          # Bytes 28-31: Volume sequence number (both-endian)
          record << [1].pack("v")
          record << [1].pack("n")

          # Byte 32: Length of file identifier
          record << [name_len].pack("C")

          # Bytes 33+: File identifier
          record << name

          # Padding byte if name length is even
          record << "\x00" if name_len.even?

          record
        end

        # Encode recording date/time (7-byte format)
        #
        # @param time [Time] Time to encode
        # @return [String] 7-byte encoded time
        def encode_record_datetime(time)
          [
            time.year - 1900,  # Years since 1900
            time.month,        # Month (1-12)
            time.day,          # Day (1-31)
            time.hour,         # Hour (0-23)
            time.min,          # Minute (0-59)
            time.sec,          # Second (0-59)
            0                  # GMT offset (0 = GMT)
          ].pack("C7")
        end

        # Write file data
        #
        # @param io [IO] Output IO
        def write_file_data(io)
          @files.each do |file_info|
            # Seek to file location
            io.seek(file_info[:location] * Iso::SECTOR_SIZE)

            # Write file data
            File.open(file_info[:source], "rb") do |src|
              while (data = src.read(Iso::SECTOR_SIZE))
                # Pad to sector boundary
                if data.bytesize < Iso::SECTOR_SIZE
                  data += "\x00" * (Iso::SECTOR_SIZE - data.bytesize)
                end
                io.write(data)
              end
            end
          end
        end
      end
    end
  end
end