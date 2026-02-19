# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "entry"

module Omnizip
  module Formats
    module Tar
      # TAR archive writer
      #
      # Creates TAR archives
      class Writer
        include Constants

        attr_reader :file_path

        # Initialize TAR writer
        #
        # @param file_path [String] Path to output TAR archive
        def initialize(file_path)
          @file_path = file_path
          @file = nil
          @closed = false
        end

        # Add a file to the TAR archive
        #
        # @param entry_name [String] Name/path in archive
        # @param source_path [String] Source file path
        # @param options [Hash] Entry options
        def add(entry_name, source_path = nil, options = {})
          source_path ||= entry_name

          unless File.exist?(source_path)
            raise ArgumentError, "File not found: #{source_path}"
          end

          open_file unless @file

          if File.directory?(source_path)
            add_directory(entry_name, source_path, options)
          elsif File.symlink?(source_path)
            add_symlink(entry_name, source_path, options)
          else
            add_file(entry_name, source_path, options)
          end
        end

        # Add a file entry
        #
        # @param entry_name [String] Name in archive
        # @param source_path [String] Source file path
        # @param options [Hash] Entry options
        def add_file(entry_name, source_path, options = {})
          open_file unless @file

          stat = File.stat(source_path)
          data = File.binread(source_path)

          entry = Entry.new(entry_name, {
                              mode: options[:mode] || (stat.mode & 0o777),
                              uid: options[:uid] || stat.uid,
                              gid: options[:gid] || stat.gid,
                              size: data.bytesize,
                              mtime: options[:mtime] || stat.mtime,
                              typeflag: TYPE_REGULAR,
                              uname: options[:uname] || "",
                              gname: options[:gname] || "",
                            })

          write_entry(entry, data)
        end

        # Add a directory entry
        #
        # @param entry_name [String] Directory name in archive
        # @param source_path [String] Source directory path (optional)
        # @param options [Hash] Entry options
        def add_directory(entry_name, source_path = nil, options = {})
          open_file unless @file

          # Ensure directory name ends with /
          entry_name = "#{entry_name}/" unless entry_name.end_with?("/")

          if source_path && File.exist?(source_path)
            stat = File.stat(source_path)
            mode = stat.mode & 0o777
            uid = stat.uid
            gid = stat.gid
            mtime = stat.mtime
          else
            mode = 0o755
            uid = 0
            gid = 0
            mtime = Time.now
          end

          entry = Entry.new(entry_name, {
                              mode: options[:mode] || mode,
                              uid: options[:uid] || uid,
                              gid: options[:gid] || gid,
                              size: 0,
                              mtime: options[:mtime] || mtime,
                              typeflag: TYPE_DIRECTORY,
                              uname: options[:uname] || "",
                              gname: options[:gname] || "",
                            })

          write_entry(entry, nil)
        end

        # Add a symbolic link entry
        #
        # @param entry_name [String] Link name in archive
        # @param source_path [String] Source symlink path
        # @param options [Hash] Entry options
        def add_symlink(entry_name, source_path, options = {})
          open_file unless @file

          linkname = File.readlink(source_path)
          stat = File.lstat(source_path)

          entry = Entry.new(entry_name, {
                              mode: options[:mode] || 0o777,
                              uid: options[:uid] || stat.uid,
                              gid: options[:gid] || stat.gid,
                              size: 0,
                              mtime: options[:mtime] || stat.mtime,
                              typeflag: TYPE_SYMLINK,
                              linkname: linkname,
                              uname: options[:uname] || "",
                              gname: options[:gname] || "",
                            })

          write_entry(entry, nil)
        end

        # Add raw entry data
        #
        # @param entry_name [String] Entry name
        # @param data [String] Entry data
        # @param options [Hash] Entry options
        def add_data(entry_name, data, options = {})
          open_file unless @file

          entry = Entry.new(entry_name, {
                              mode: options[:mode] || 0o644,
                              uid: options[:uid] || 0,
                              gid: options[:gid] || 0,
                              size: data.bytesize,
                              mtime: options[:mtime] || Time.now,
                              typeflag: TYPE_REGULAR,
                              uname: options[:uname] || "",
                              gname: options[:gname] || "",
                            })

          write_entry(entry, data)
        end

        # Close the TAR archive
        def close
          return if @closed

          if @file
            # Write two zero blocks to mark end of archive
            @file.write("\0" * BLOCK_SIZE * 2)
            @file.close
          end

          @closed = true
        end

        # Create TAR archive with block syntax
        #
        # @param file_path [String] Path to output TAR archive
        # @yield [Writer] Writer instance
        def self.create(file_path)
          writer = new(file_path)
          yield writer if block_given?
          writer.close
          writer
        end

        private

        # Open output file
        def open_file
          @file = File.open(@file_path, "wb")
        end

        # Write an entry to the archive
        #
        # @param entry [Entry] Entry to write
        # @param data [String, nil] Entry data
        def write_entry(entry, data)
          # Write header
          header = Header.build(entry)
          @file.write(header)

          # Write data if present
          if data && !data.empty?
            @file.write(data)

            # Pad to block boundary
            remainder = data.bytesize % BLOCK_SIZE
            if remainder.positive?
              padding = BLOCK_SIZE - remainder
              @file.write("\0" * padding)
            end
          end
        end
      end
    end
  end
end
