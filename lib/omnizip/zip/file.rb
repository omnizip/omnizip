# frozen_string_literal: true

require "fileutils"
require_relative "entry"
require_relative "../formats/zip/reader"
require_relative "../formats/zip/writer"
require_relative "../extraction"
require_relative "../metadata/archive_metadata"

module Omnizip
  module Zip
    # Rubyzip-compatible File class
    # Provides drop-in replacement for Zip::File from rubyzip
    class File
      attr_reader :name, :entries, :comment

      # Open a ZIP archive
      # @param file_path [String] Path to ZIP file
      # @param create [Boolean] Create file if it doesn't exist
      # @param options [Hash] Additional options
      # @yield [file] Block to execute with the opened archive
      # @return [File] The opened archive (if no block given)
      def self.open(file_path, create: false, **options, &block)
        file = new(file_path, create: create, **options)

        if block_given?
          begin
            block.call(file)
          ensure
            file.close
          end
        else
          file
        end
      end

      # Create a new archive from scratch
      # @param file_path [String] Path to ZIP file
      # @yield [file] Block to execute with the new archive
      def self.create(file_path, &block)
        open(file_path, create: true, &block)
      end

      # Initialize a ZIP file
      # @param file_path [String] Path to ZIP file
      # @param create [Boolean] Create file if it doesn't exist
      def initialize(file_path, create: false, **options)
        @name = file_path
        @entries = []
        @comment = ""
        @create = create
        @options = options
        @modified = false
        @reader = nil
        @writer = nil

        # Load existing archive if it exists
        if ::File.exist?(file_path) && !create
          load_archive
        elsif create
          # Will create on write/close
          @modified = true
        elsif !::File.exist?(file_path)
          raise Errno::ENOENT, "No such file or directory - #{file_path}"
        end
      end

      # Add a file to the archive
      # @param entry_name [String] Name in the archive
      # @param src_path [String, nil] Source file path (optional if block given)
      # @yield Block that returns content to add
      def add(entry_name, src_path = nil, &block)
        # Handle directory entries (ending with /)
        if entry_name.end_with?("/") && !src_path && !block_given?
          add_directory(entry_name)
        elsif block_given?
          data = block.call
          add_data(entry_name, data)
        elsif src_path
          add_file_from_path(entry_name, src_path)
        else
          raise ArgumentError, "Either src_path or block must be provided"
        end

        @modified = true
        self
      end

      # Get entry by name
      # @param entry_name [String] Name of the entry
      # @return [Entry, nil] The entry or nil if not found
      def get_entry(entry_name)
        entries.find { |e| e.name == entry_name }
      end
      alias_method :find_entry, :get_entry

      # Get input stream for an entry
      # @param entry [Entry, String] Entry object or name
      # @yield [stream] Block to read from the stream
      # @return [String] Entry content (if no block given)
      def get_input_stream(entry, &block)
        entry = get_entry(entry) if entry.is_a?(String)
        raise Errno::ENOENT, "Entry not found: #{entry}" unless entry

        content = read_entry_data(entry)

        if block_given?
          require "stringio"
          StringIO.open(content, "rb", &block)
        else
          content
        end
      end
      alias_method :read, :get_input_stream

      # Iterate over all entries
      # @yield [entry] Block to execute for each entry
      def each(&block)
        entries.each(&block)
      end

      # Extract an entry to a destination path
      # @param entry [Entry, String] Entry object or name
      # @param dest_path [String] Destination file path
      def extract(entry, dest_path, &on_exists_proc)
        entry = get_entry(entry) if entry.is_a?(String)
        raise Errno::ENOENT, "Entry not found: #{entry}" unless entry

        # Handle existing file
        if ::File.exist?(dest_path)
          if on_exists_proc
            action = on_exists_proc.call(entry, dest_path)
            return if action == false
          else
            raise "Destination file already exists: #{dest_path}"
          end
        end

        extract_entry_to_path(entry, dest_path)
      end

      # Remove an entry from the archive
      # @param entry_name [String] Name of the entry to remove
      def remove(entry_name)
        entry = get_entry(entry_name)
        @entries.delete(entry) if entry
        @modified = true
        @reader = nil
        self
      end

      # Rename an entry
      # @param entry_name [String] Current entry name
      # @param new_name [String] New entry name
      def rename(entry_name, new_name)
        entry = get_entry(entry_name)
        return unless entry

        entry.header.filename = new_name
        @modified = true
        self
      end

      # Replace entry content
      # @param entry_name [String] Entry name
      # @param src_path [String, nil] Source file path
      def replace(entry_name, src_path = nil, &block)
        remove(entry_name)
        add(entry_name, src_path, &block)
      end

      # Get archive comment
      def comment
        @comment
      end

      # Set archive comment
      def comment=(value)
        @comment = value.to_s
        @modified = true
      end

      # Get number of entries
      def size
        entries.size
      end
      alias_method :length, :size

      # Check if archive contains an entry
      # @param entry_name [String] Entry name to check
      # @return [Boolean] True if entry exists
      def include?(entry_name)
        !get_entry(entry_name).nil?
      end

      # Get names of all entries
      # @return [Array<String>] Array of entry names
      def names
        entries.map(&:name)
      end

      # Glob entries by pattern
      # @param pattern [String] Glob pattern
      # @return [Array<Entry>] Matching entries
      def glob(pattern, &block)
        require "fnmatch"
        matching = entries.select { |e| ::File.fnmatch(pattern, e.name) }

        if block_given?
          matching.each(&block)
        else
          matching
        end
      end

      # Extract files matching a pattern
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @param dest [String] Destination directory
      # @param options [Hash] Extraction options
      # @option options [Boolean] :preserve_paths Keep directory structure
      # @option options [Boolean] :flatten Extract all to destination root
      # @option options [Boolean] :overwrite Overwrite existing files
      # @return [Array<String>] Paths of extracted files
      def extract_matching(pattern, dest, options = {})
        Omnizip::Extraction.extract_matching(self, pattern, dest, options)
      end

      # Extract files matching a pattern to memory
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Hash<String, String>] Hash of filename => content
      def extract_matching_to_memory(pattern)
        Omnizip::Extraction.extract_to_memory_matching(self, pattern)
      end

      # List files matching a pattern
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Array<Entry>] Matching entries
      def list_matching(pattern)
        Omnizip::Extraction.list_matching(self, pattern)
      end

      # Count files matching a pattern
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Integer] Number of matches
      def count_matching(pattern)
        Omnizip::Extraction.count_matching(self, pattern)
      end

      # Extract with a filter chain
      # @param filter [Omnizip::Extraction::FilterChain] Filter chain
      # @param dest [String] Destination directory
      # @param options [Hash] Extraction options
      # @return [Array<String>] Paths of extracted files
      def extract_with_filter(filter, dest, options = {})
        Omnizip::Extraction.extract_with_filter(self, filter, dest, options)
      end

      # Get archive metadata
      # @return [Omnizip::Metadata::ArchiveMetadata] Archive metadata
      def metadata
        @archive_metadata ||= Omnizip::Metadata::ArchiveMetadata.new(self)
      end

      # Save metadata changes
      # Marks the archive as modified so changes are written on close
      def save_metadata
        @modified = true
        metadata.reset_modified
      end

      # Commit changes to disk
      def commit
        write_archive if @modified
        @modified = false
        @reader = nil  # Invalidate reader after writing
      end

      # Close the archive
      def close
        commit if @modified
        @reader = nil
        @writer = nil
      end

      private

      # Load existing archive
      def load_archive
        @reader = Omnizip::Formats::Zip::Reader.new(@name)
        @reader.read

        @entries = @reader.entries.map { |header| Entry.new(header, filepath: @name) }
      end

      # Add file from filesystem path
      def add_file_from_path(entry_name, src_path)
        unless ::File.exist?(src_path)
          raise Errno::ENOENT, "Source file not found: #{src_path}"
        end

        if ::File.directory?(src_path)
          add_directory(entry_name)
        else
          data = ::File.binread(src_path)
          stat = ::File.stat(src_path)
          add_data(entry_name, data, stat: stat)
        end
      end

      # Add data directly
      def add_data(entry_name, data, stat: nil)
        # Remove existing entry with same name
        remove(entry_name)

        # Create new header
        header = create_header(entry_name, data, stat: stat)
        entry = Entry.new(header, filepath: @name)
        @entries << entry

        # Invalidate reader cache since we modified entries
        @reader = nil
      end

      # Add directory entry
      def add_directory(entry_name)
        entry_name = entry_name.end_with?("/") ? entry_name : "#{entry_name}/"
        header = create_header(entry_name, "", directory: true)
        entry = Entry.new(header, filepath: @name)
        @entries << entry
      end

      # Create a central directory header
      def create_header(filename, data, stat: nil, directory: false)
        require_relative "../formats/zip/central_directory_header"

        now = Time.now
        crc32 = directory ? 0 : Omnizip::Checksums::Crc32.new.tap { |c| c.update(data) }.value

        external_attrs = if directory
                          Omnizip::Formats::Zip::Constants::UNIX_DIR_PERMISSIONS |
                            Omnizip::Formats::Zip::Constants::ATTR_DIRECTORY
                        elsif stat
                          (stat.mode & 0o777) << 16
                        else
                          Omnizip::Formats::Zip::Constants::UNIX_FILE_PERMISSIONS
                        end

        Omnizip::Formats::Zip::CentralDirectoryHeader.new(
          version_made_by: Omnizip::Formats::Zip::Constants::VERSION_MADE_BY_UNIX |
                          Omnizip::Formats::Zip::Constants::VERSION_DEFAULT,
          version_needed: Omnizip::Formats::Zip::Constants::VERSION_DEFAULT,
          flags: Omnizip::Formats::Zip::Constants::FLAG_UTF8,
          compression_method: directory ? 0 : 8, # Store or Deflate
          last_mod_time: dos_time(now),
          last_mod_date: dos_date(now),
          crc32: crc32,
          compressed_size: 0, # Will be set during write
          uncompressed_size: data.bytesize,
          disk_number_start: 0,
          internal_attributes: 0,
          external_attributes: external_attrs,
          local_header_offset: 0, # Will be set during write
          filename: filename,
          extra_field: "",
          comment: ""
        ).tap do |header|
          # Store original data in header for writing
          header.instance_variable_set(:@_original_data, data)
        end
      end

      # Read entry data from archive
      def read_entry_data(entry)
        return "" if entry.directory?

        # Check if we have cached data (for new entries not yet written)
        cached_data = entry.header.instance_variable_get(:@_original_data)
        return cached_data if cached_data

        # Otherwise read from file
        unless @reader
          @reader = Omnizip::Formats::Zip::Reader.new(@name)
          @reader.read
        end

        ::File.open(@name, "rb") do |io|
          # Find the entry in reader
          reader_entry = @reader.entries.find { |e| e.filename == entry.name }
          raise "Entry not found in archive: #{entry.name}" unless reader_entry

          # Extract just the data
          io.seek(reader_entry.local_header_offset, ::IO::SEEK_SET)

          # Read and parse local file header
          fixed_header = io.read(30)
          return "" unless fixed_header && fixed_header.size == 30

          _signature, _version, _flags, _method, _time, _date, _crc32,
          _comp_size, _uncomp_size, filename_length, extra_length = fixed_header.unpack("VvvvvvVVVvv")

          # Skip filename and extra field
          io.read(filename_length + extra_length)

          # Read compressed data
          compressed_data = io.read(reader_entry.compressed_size)
          return "" unless compressed_data

          # Decompress
          @reader.send(:decompress_data,
                      compressed_data,
                      reader_entry.compression_method,
                      reader_entry.uncompressed_size)
        end
      end

      # Extract entry to filesystem
      def extract_entry_to_path(entry, dest_path)
        if entry.directory?
          FileUtils.mkdir_p(dest_path)
        else
          FileUtils.mkdir_p(::File.dirname(dest_path))
          content = read_entry_data(entry)
          ::File.binwrite(dest_path, content)

          # Set permissions if Unix
          if entry.unix_perms > 0
            ::File.chmod(entry.unix_perms & 0o777, dest_path)
          end
        end
      end

      # Write archive to disk
      def write_archive
        # Cache all entry data before writing (to avoid reading while writing)
        entry_data = {}
        entries.each do |entry|
          next if entry.directory?
          header = entry.header
          cached = header.instance_variable_get(:@_original_data)
          entry_data[entry.name] = cached || read_entry_data(entry)
        end

        writer = Omnizip::Formats::Zip::Writer.new(@name)

        entries.each do |entry|
          if entry.directory?
            writer.add_directory(entry.name)
          else
            writer.add_data(entry.name, entry_data[entry.name])
          end
        end

        writer.write
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