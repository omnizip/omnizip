# frozen_string_literal: true

module Omnizip
  # Convenience methods for common archive operations
  module Convenience
    # Compress a single file to a ZIP archive
    # @param input_path [String] Path to input file
    # @param output_path [String] Path to output ZIP file
    # @param options [Hash] Compression options
    # @option options [Symbol, Omnizip::Profile::CompressionProfile] :profile
    #   Compression profile (:fast, :balanced, :maximum, :text, :binary, :archive, :auto)
    # @option options [Symbol] :compression Compression method (:deflate, :bzip2, :lzma, :zstandard)
    # @option options [Integer] :level Compression level (1-9)
    # @option options [Boolean] :chunked Use chunked processing for large files
    # @option options [Integer] :chunk_size Chunk size in bytes (default: 64MB)
    # @option options [Integer] :max_memory Maximum memory usage (default: 256MB)
    # @option options [Proc] :progress Progress callback
    # @return [String] Path to created archive
    #
    # @example
    #   Omnizip.compress_file('document.txt', 'document.zip')
    #   Omnizip.compress_file('image.png', 'image.zip', compression: :lzma, level: 9)
    #   Omnizip.compress_file('huge.dat', 'huge.zip', chunked: true, max_memory: 128.megabytes)
    #   Omnizip.compress_file('data.txt', 'data.zip', profile: :fast)
    #   Omnizip.compress_file('app.exe', 'app.zip', profile: :auto)
    def compress_file(input_path, output_path, **options)
      raise Errno::ENOENT, "Input file not found: #{input_path}" unless ::File.exist?(input_path)
      raise ArgumentError, "Input is a directory: #{input_path}" if ::File.directory?(input_path)

      # Apply profile settings if specified
      options = apply_profile(input_path, options) if options[:profile]

      # Use chunked processing for large files if requested
      if options[:chunked]
        return Omnizip::Chunked.compress_file(input_path, output_path, **options)
      end

      Omnizip::Zip::File.create(output_path) do |zip|
        basename = ::File.basename(input_path)
        zip.add(basename, input_path)
      end

      output_path
    end

    # Compress a directory to a ZIP archive
    # @param input_dir [String] Path to input directory
    # @param output_path [String] Path to output ZIP file
    # @param options [Hash] Compression options
    # @option options [Symbol, Omnizip::Profile::CompressionProfile] :profile
    #   Compression profile (:fast, :balanced, :maximum, etc.)
    # @option options [Symbol] :compression Compression method
    # @option options [Integer] :level Compression level (1-9)
    # @option options [Boolean] :recursive Include subdirectories (default: true)
    # @option options [Integer] :max_memory Maximum memory usage for large files
    # @option options [Proc] :progress Progress callback
    # @return [String] Path to created archive
    #
    # @example
    #   Omnizip.compress_directory('project/', 'backup.zip')
    #   Omnizip.compress_directory('src/', 'src.zip', compression: :lzma2, level: 9)
    #   Omnizip.compress_directory('large/', 'backup.zip', max_memory: 256.megabytes)
    #   Omnizip.compress_directory('src/', 'backup.7z', profile: :maximum)
    def compress_directory(input_dir, output_path, recursive: true, **options)
      raise Errno::ENOENT, "Input directory not found: #{input_dir}" unless ::File.exist?(input_dir)
      raise ArgumentError, "Input is not a directory: #{input_dir}" unless ::File.directory?(input_dir)

      # Apply profile settings if specified (use first file for auto-detection)
      if options[:profile]
        first_file = find_first_file(input_dir)
        options = apply_profile(first_file, options)
      end

      Omnizip::Zip::File.create(output_path) do |zip|
        add_directory_contents(zip, input_dir, "", recursive: recursive)
      end

      output_path
    end

    # Extract a ZIP archive to a directory
    # @param archive_path [String] Path to ZIP archive
    # @param output_dir [String] Path to output directory
    # @param options [Hash] Extraction options
    # @option options [Boolean] :overwrite Overwrite existing files (default: false)
    # @return [Array<String>] List of extracted file paths
    #
    # @example
    #   Omnizip.extract_archive('backup.zip', 'restore/')
    #   Omnizip.extract_archive('archive.zip', 'output/', overwrite: true)
    def extract_archive(archive_path, output_dir, overwrite: false, **options)
      raise Errno::ENOENT, "Archive not found: #{archive_path}" unless ::File.exist?(archive_path)

      extracted_files = []

      Omnizip::Zip::File.open(archive_path) do |zip|
        zip.each do |entry|
          dest_path = ::File.join(output_dir, entry.name)

          # Handle overwrite option
          on_exists = if overwrite
                        proc { true }
                      else
                        proc { |e, path| raise "File exists: #{path}" }
                      end

          zip.extract(entry, dest_path, &on_exists)
          extracted_files << dest_path
        end
      end

      extracted_files
    end

    # List contents of a ZIP archive
    # @param archive_path [String] Path to ZIP archive
    # @param options [Hash] Listing options
    # @option options [Boolean] :details Include detailed information (default: false)
    # @return [Array<String>, Array<Hash>] List of entry names or detailed info
    #
    # @example
    #   Omnizip.list_archive('backup.zip')
    #   # => ["file1.txt", "file2.txt", "dir/"]
    #
    #   Omnizip.list_archive('backup.zip', details: true)
    #   # => [{name: "file1.txt", size: 1024, compressed_size: 512, ...}, ...]
    def list_archive(archive_path, details: false, **options)
      raise Errno::ENOENT, "Archive not found: #{archive_path}" unless ::File.exist?(archive_path)

      Omnizip::Zip::File.open(archive_path) do |zip|
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

    # Read a single file from a ZIP archive
    # @param archive_path [String] Path to ZIP archive
    # @param entry_name [String] Name of entry to read
    # @return [String] Contents of the file
    #
    # @example
    #   content = Omnizip.read_from_archive('backup.zip', 'config.yml')
    def read_from_archive(archive_path, entry_name)
      raise Errno::ENOENT, "Archive not found: #{archive_path}" unless ::File.exist?(archive_path)

      Omnizip::Zip::File.open(archive_path) do |zip|
        entry = zip.get_entry(entry_name)
        raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

        zip.read(entry)
      end
    end

    # Add a file to an existing ZIP archive
    # @param archive_path [String] Path to ZIP archive
    # @param entry_name [String] Name for entry in archive
    # @param source_path [String] Path to source file
    # @return [String] Path to archive
    #
    # @example
    #   Omnizip.add_to_archive('backup.zip', 'new_file.txt', 'path/to/new_file.txt')
    def add_to_archive(archive_path, entry_name, source_path)
      raise Errno::ENOENT, "Archive not found: #{archive_path}" unless ::File.exist?(archive_path)
      raise Errno::ENOENT, "Source file not found: #{source_path}" unless ::File.exist?(source_path)

      Omnizip::Zip::File.open(archive_path) do |zip|
        zip.add(entry_name, source_path)
      end

      archive_path
    end

    # Remove a file from a ZIP archive
    # @param archive_path [String] Path to ZIP archive
    # @param entry_name [String] Name of entry to remove
    # @return [String] Path to archive
    #
    # @example
    #   Omnizip.remove_from_archive('backup.zip', 'old_file.txt')
    def remove_from_archive(archive_path, entry_name)
      raise Errno::ENOENT, "Archive not found: #{archive_path}" unless ::File.exist?(archive_path)

      Omnizip::Zip::File.open(archive_path) do |zip|
        zip.remove(entry_name)
      end

      archive_path
    end

    private

    # Apply compression profile to options
    #
    # @param file_path [String, nil] File path for auto-detection
    # @param options [Hash] Compression options
    # @return [Hash] Updated options with profile settings
    def apply_profile(file_path, options)
      profile_spec = options.delete(:profile)
      return options unless profile_spec

      # Get the profile
      profile = case profile_spec
                when :auto
                  # Auto-detect based on file
                  file_path ? Omnizip::Profile.detect(file_path) : Omnizip::Profile.get(:balanced)
                when Symbol
                  # Get by name
                  Omnizip::Profile.get(profile_spec) || Omnizip::Profile.get(:balanced)
                when Omnizip::Profile::CompressionProfile
                  # Use the profile directly
                  profile_spec
                else
                  Omnizip::Profile.get(:balanced)
                end

      # Apply profile to options
      profile.apply_to(options)
    end

    # Find first file in directory for profile detection
    #
    # @param dir_path [String] Directory path
    # @return [String, nil] Path to first file or nil
    def find_first_file(dir_path)
      Dir.foreach(dir_path) do |entry|
        next if entry == "." || entry == ".."

        full_path = ::File.join(dir_path, entry)
        return full_path if ::File.file?(full_path)

        # Check subdirectories
        if ::File.directory?(full_path)
          result = find_first_file(full_path)
          return result if result
        end
      end
      nil
    end

    # Recursively add directory contents to archive
    def add_directory_contents(zip, base_dir, relative_path, recursive: true)
      dir_path = ::File.join(base_dir, relative_path)

      Dir.foreach(dir_path) do |entry|
        next if entry == "." || entry == ".."

        full_path = ::File.join(dir_path, entry)
        archive_path = ::File.join(relative_path, entry)

        if ::File.directory?(full_path)
          zip.add("#{archive_path}/")
          add_directory_contents(zip, base_dir, archive_path, recursive: recursive) if recursive
        else
          zip.add(archive_path, full_path)
        end
      end
    end
  end

  # Extend Omnizip module with convenience methods
  extend Convenience
end