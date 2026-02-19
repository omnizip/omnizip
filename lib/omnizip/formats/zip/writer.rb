# frozen_string_literal: true

require "fileutils"
require_relative "constants"
require_relative "local_file_header"
require_relative "central_directory_header"
require_relative "end_of_central_directory"
require_relative "unix_extra_field"
require_relative "../../link_handler"

module Omnizip
  module Formats
    module Zip
      # ZIP archive writer
      class Writer
        include Constants

        attr_reader :file_path, :entries

        def initialize(file_path)
          @file_path = file_path
          @entries = []
          @local_headers = []
        end

        # Add a file to the archive
        def add_file(file_path, archive_path = nil, preserve_links: true)
          archive_path ||= File.basename(file_path)

          if File.directory?(file_path)
            add_directory(archive_path)
          elsif preserve_links && LinkHandler.symlink?(file_path)
            add_symlink(archive_path, LinkHandler.read_link_target(file_path))
          elsif preserve_links && LinkHandler.hardlink?(file_path)
            # For hard links, we add as regular file but track inode
            data = File.binread(file_path)
            add_data(archive_path, data, File.stat(file_path))
          else
            data = File.binread(file_path)
            add_data(archive_path, data, File.stat(file_path))
          end
        end

        # Add a symbolic link to the archive
        def add_symlink(archive_path, target)
          unless LinkHandler.symlink_supported?
            warn "Warning: Symbolic links not supported on #{RUBY_PLATFORM}, storing as regular file"
            add_data(archive_path, target)
            return
          end

          entry = create_entry(
            filename: archive_path,
            uncompressed_data: target,
            symlink: true,
            symlink_target: target,
          )

          @entries << entry
        end

        # Add a hard link to the archive
        def add_hardlink(archive_path, target_path)
          unless LinkHandler.hardlink_supported?
            warn "Warning: Hard links not supported on #{RUBY_PLATFORM}, storing as regular file"
            # Store the target file content instead
            if File.exist?(target_path)
              data = File.binread(target_path)
              add_data(archive_path, data, File.stat(target_path))
            else
              add_data(archive_path, "")
            end
            return
          end

          # For hard links, we store the first occurrence as a regular file
          # and subsequent ones reference the original
          entry = create_entry(
            filename: archive_path,
            uncompressed_data: "",
            hardlink: true,
            hardlink_target: target_path,
          )

          @entries << entry
        end

        # Add a directory to the archive
        def add_directory(archive_path)
          archive_path = "#{archive_path}/" unless archive_path.end_with?("/")

          entry = create_entry(
            filename: archive_path,
            uncompressed_data: "",
            directory: true,
          )

          @entries << entry
        end

        # Add data directly to the archive
        def add_data(archive_path, data, stat = nil)
          entry = create_entry(
            filename: archive_path,
            uncompressed_data: data,
            stat: stat,
          )

          @entries << entry
        end

        # Write the archive to disk
        def write(compression_method: COMPRESSION_DEFLATE, level: 6)
          File.open(file_path, "wb") do |io|
            write_to_io(io, compression_method: compression_method,
                            level: level)
          end
        end

        # Write to an IO object
        def write_to_io(io, compression_method: COMPRESSION_DEFLATE, level: 6)
          local_header_offsets = []

          # Write local file headers and data
          entries.each do |entry|
            offset = io.pos
            local_header_offsets << offset

            # Create local file header
            local_header = create_local_header(entry, compression_method)

            # Compress data if not a directory
            if entry[:directory]
              compressed_data = ""
              entry[:compressed_size] = 0
              entry[:uncompressed_size] = 0
              entry[:crc32] = 0
            else
              compressed_data = compress_data(
                entry[:uncompressed_data],
                compression_method,
                level,
              )
              entry[:compressed_size] = compressed_data.bytesize
              entry[:uncompressed_size] = entry[:uncompressed_data].bytesize
              entry[:crc32] = calculate_crc32(entry[:uncompressed_data])
            end

            # Update local header with compressed sizes
            local_header.compressed_size = entry[:compressed_size]
            local_header.uncompressed_size = entry[:uncompressed_size]
            local_header.crc32 = entry[:crc32]

            # Write local header
            io.write(local_header.to_binary)

            # Write compressed data
            io.write(compressed_data) unless entry[:directory]
          end

          # Record start of central directory
          central_directory_offset = io.pos

          # Write central directory headers
          entries.each_with_index do |entry, index|
            central_header = create_central_header(
              entry,
              compression_method,
              local_header_offsets[index],
            )
            io.write(central_header.to_binary)
          end

          # Calculate central directory size
          central_directory_size = io.pos - central_directory_offset

          # Write end of central directory record
          eocd = create_eocd(
            total_entries: entries.size,
            central_directory_size: central_directory_size,
            central_directory_offset: central_directory_offset,
          )
          io.write(eocd.to_binary)
        end

        private

        # Create an entry hash
        def create_entry(
          filename:,
          uncompressed_data:,
          directory: false,
          stat: nil,
          symlink: false,
          symlink_target: nil,
          hardlink: false,
          hardlink_target: nil
        )
          now = Time.now

          {
            filename: filename,
            uncompressed_data: uncompressed_data,
            directory: directory,
            stat: stat,
            mtime: now,
            compressed_size: 0,
            uncompressed_size: uncompressed_data.bytesize,
            crc32: 0,
            symlink: symlink,
            symlink_target: symlink_target,
            hardlink: hardlink,
            hardlink_target: hardlink_target,
          }
        end

        # Create local file header from entry
        def create_local_header(entry, compression_method)
          mtime = entry[:mtime]

          LocalFileHeader.new(
            version_needed: version_for_method(compression_method),
            flags: FLAG_UTF8,
            compression_method: entry[:directory] ? COMPRESSION_STORE : compression_method,
            last_mod_time: dos_time(mtime),
            last_mod_date: dos_date(mtime),
            crc32: 0, # Will be updated after compression
            compressed_size: 0, # Will be updated after compression
            uncompressed_size: 0, # Will be updated after compression
            filename: entry[:filename],
          )
        end

        # Create central directory header from entry
        def create_central_header(entry, compression_method,
local_header_offset)
          mtime = entry[:mtime]

          # Build extra field for links
          extra_field = ""
          if entry[:symlink] && entry[:symlink_target]
            unix_field = UnixExtraField.for_symlink(entry[:symlink_target])
            extra_field = unix_field.to_binary
          elsif entry[:hardlink] && entry[:hardlink_target]
            unix_field = UnixExtraField.for_hardlink
            extra_field = unix_field.to_binary
          end

          external_attrs = if entry[:directory]
                             UNIX_DIR_PERMISSIONS | ATTR_DIRECTORY
                           elsif entry[:symlink]
                             UNIX_SYMLINK_PERMISSIONS
                           elsif entry[:stat]
                             (entry[:stat].mode & 0o777) << 16
                           else
                             UNIX_FILE_PERMISSIONS
                           end

          CentralDirectoryHeader.new(
            version_made_by: VERSION_MADE_BY_UNIX | version_for_method(compression_method),
            version_needed: version_for_method(compression_method),
            flags: FLAG_UTF8,
            compression_method: entry[:directory] ? COMPRESSION_STORE : compression_method,
            last_mod_time: dos_time(mtime),
            last_mod_date: dos_date(mtime),
            crc32: entry[:crc32],
            compressed_size: entry[:compressed_size],
            uncompressed_size: entry[:uncompressed_size],
            disk_number_start: 0,
            internal_attributes: 0,
            external_attributes: external_attrs,
            local_header_offset: local_header_offset,
            filename: entry[:filename],
            extra_field: extra_field,
          )
        end

        # Create end of central directory record
        def create_eocd(total_entries:, central_directory_size:,
central_directory_offset:)
          EndOfCentralDirectory.new(
            disk_number: 0,
            disk_number_with_cd: 0,
            total_entries_this_disk: total_entries,
            total_entries: total_entries,
            central_directory_size: central_directory_size,
            central_directory_offset: central_directory_offset,
          )
        end

        # Compress data based on compression method
        def compress_data(data, method, level)
          case method
          when COMPRESSION_STORE
            data
          when COMPRESSION_DEFLATE
            compress_deflate(data, level)
          when COMPRESSION_BZIP2
            compress_bzip2(data, level)
          when COMPRESSION_LZMA
            compress_lzma(data, level)
          when COMPRESSION_ZSTANDARD
            compress_zstandard(data, level)
          else
            raise Omnizip::UnsupportedFormatError,
                  "Unsupported compression method: #{method}"
          end
        end

        # Compress using Deflate
        def compress_deflate(data, level)
          require "zlib"
          # ZIP uses raw deflate without zlib wrapper
          Zlib::Deflate.new(level, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
        rescue StandardError => e
          raise Omnizip::CompressionError,
                "Deflate compression failed: #{e.message}"
        end

        # Compress using BZip2
        def compress_bzip2(data, level)
          algorithm = AlgorithmRegistry.get(:bzip2)
          algorithm.compress(data, level: level)
        rescue StandardError => e
          raise Omnizip::CompressionError,
                "BZip2 compression failed: #{e.message}"
        end

        # Compress using LZMA
        def compress_lzma(data, level)
          algorithm = AlgorithmRegistry.get(:lzma)
          algorithm.compress(data, level: level)
        rescue StandardError => e
          raise Omnizip::CompressionError,
                "LZMA compression failed: #{e.message}"
        end

        # Compress using Zstandard
        def compress_zstandard(data, level)
          algorithm = AlgorithmRegistry.get(:zstandard)
          algorithm.compress(data, level: level)
        rescue StandardError => e
          raise Omnizip::CompressionError,
                "Zstandard compression failed: #{e.message}"
        end

        # Calculate CRC32 checksum
        def calculate_crc32(data)
          Omnizip::Checksums::Crc32.new.tap { |c| c.update(data) }.finalize
        end

        # Get version needed for compression method
        def version_for_method(method)
          case method
          when COMPRESSION_STORE then VERSION_DEFAULT
          when COMPRESSION_DEFLATE then VERSION_DEFLATE
          when COMPRESSION_BZIP2 then VERSION_BZIP2
          when COMPRESSION_LZMA then VERSION_LZMA
          else VERSION_DEFAULT
          end
        end

        # Convert Time to DOS time format
        def dos_time(time)
          ((time.hour << 11) | (time.min << 5) | (time.sec / 2)) & 0xFFFF
        end

        # Convert Time to DOS date format
        def dos_date(time)
          (((time.year - 1980) << 9) | (time.month << 5) | time.day) & 0xFFFF
        end
      end
    end
  end
end
