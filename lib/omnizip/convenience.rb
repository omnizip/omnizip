# frozen_string_literal: true

module Omnizip
  # Convenience methods for common archive operations.
  #
  # All public methods accept an optional +format:+ keyword (default
  # +:zip+) that selects the underlying archive handler via
  # +Omnizip::ArchiveHandler+. New formats gain access to the convenience
  # API by registering a handler; no edits to this file are needed.
  module Convenience
    DEFAULT_FORMAT = :zip

    # Compress a single file into an archive.
    #
    # @param input_path [String] Path to input file
    # @param output_path [String] Path to output archive
    # @param format [Symbol] Archive format (default +:zip+)
    # @param options [Hash] Compression / format-specific options
    # @return [String] +output_path+
    def compress_file(input_path, output_path, format: DEFAULT_FORMAT, **options)
      unless ::File.exist?(input_path)
        raise Errno::ENOENT, "Input file not found: #{input_path}"
      end
      if ::File.directory?(input_path)
        raise ArgumentError, "Input is a directory: #{input_path}"
      end

      options = apply_profile(input_path, options) if options[:profile]

      if options[:chunked]
        return Omnizip::Chunked.compress_file(input_path, output_path, **options)
      end

      # Single-file compression formats route by output extension
      # (unless an archive format was requested explicitly): writing
      # output.lzma through the archive path silently produced a ZIP
      # under a foreign extension.
      if format == DEFAULT_FORMAT && (handler = single_file_handler(output_path))
        handler.call(input_path, output_path, options)
        return output_path
      end

      Omnizip::ArchiveHandler.for(resolve_archive_format(output_path, format)).create(output_path) do |archive|
        archive.add(::File.basename(input_path), input_path)
      end

      output_path
    end

    # Compress a directory into an archive.
    #
    # @param input_dir [String] Path to input directory
    # @param output_path [String] Path to output archive
    # @param format [Symbol] Archive format (default +:zip+)
    # @param recursive [Boolean] Include subdirectories (default +true+)
    # @param options [Hash] Compression / format-specific options
    # @return [String] +output_path+
    def compress_directory(input_dir, output_path, format: DEFAULT_FORMAT,
                           recursive: true, **options)
      unless ::File.exist?(input_dir)
        raise Errno::ENOENT, "Input directory not found: #{input_dir}"
      end
      unless ::File.directory?(input_dir)
        raise ArgumentError, "Input is not a directory: #{input_dir}"
      end

      if options[:profile]
        first_file = find_first_file(input_dir)
        apply_profile(first_file, options)
      end

      Omnizip::ArchiveHandler.for(resolve_archive_format(output_path, format)).create(output_path) do |archive|
        add_directory_contents(archive, input_dir, "", recursive: recursive)
      end

      output_path
    end

    # Extract an archive to a directory.
    #
    # @param archive_path [String] Path to archive
    # @param output_dir [String] Output directory
    # @param format [Symbol] Archive format (default +:zip+)
    # @param overwrite [Boolean] Overwrite existing files (default +false+)
    # @param options [Hash] Format-specific extraction options
    # @return [Array<String>] Extracted file paths
    def extract_archive(archive_path, output_dir, format: DEFAULT_FORMAT,
                        overwrite: false, **options)
      require_archive!(archive_path)
      Omnizip::ArchiveHandler.for(resolve_archive_format(archive_path, format))
        .extract_to(archive_path, output_dir,
                    overwrite: overwrite, **options)
    end

    # List contents of an archive.
    #
    # @param archive_path [String] Path to archive
    # @param format [Symbol] Archive format (default +:zip+)
    # @param details [Boolean] Include detailed info (default +false+)
    # @param options [Hash] Format-specific listing options
    # @return [Array<String>, Array<Hash>]
    def list_archive(archive_path, format: DEFAULT_FORMAT, details: false,
                     **options)
      require_archive!(archive_path)
      Omnizip::ArchiveHandler.for(resolve_archive_format(archive_path, format))
        .list(archive_path, details: details, **options)
    end

    # Read a single entry from an archive.
    #
    # @param archive_path [String] Path to archive
    # @param entry_name [String] Entry to read
    # @param format [Symbol] Archive format (default +:zip+)
    # @return [String] Entry contents
    def read_from_archive(archive_path, entry_name, format: DEFAULT_FORMAT)
      require_archive!(archive_path)
      Omnizip::ArchiveHandler.for(resolve_archive_format(archive_path, format)).read_entry(archive_path, entry_name)
    end

    # Add a file to an existing archive.
    #
    # @param archive_path [String] Path to archive
    # @param entry_name [String] Entry name in archive
    # @param source_path [String] Path to source file
    # @param format [Symbol] Archive format (default +:zip+)
    # @return [String] +archive_path+
    def add_to_archive(archive_path, entry_name, source_path,
                       format: DEFAULT_FORMAT)
      require_archive!(archive_path)
      unless ::File.exist?(source_path)
        raise Errno::ENOENT, "Source file not found: #{source_path}"
      end

      resolved = resolve_archive_format(archive_path, format)
      handler = Omnizip::ArchiveHandler.for(resolved)
      # allowed: handler is a registered duck; missing add_entry raises below
      if handler.respond_to?(:add_entry)
        handler.add_entry(archive_path, entry_name, source_path)
      else
        raise Omnizip::UnsupportedFormatError,
              "Format #{resolved.inspect} does not support adding entries"
      end

      archive_path
    end

    # Remove an entry from an existing archive.
    #
    # @param archive_path [String] Path to archive
    # @param entry_name [String] Entry to remove
    # @param format [Symbol] Archive format (default +:zip+)
    # @return [String] +archive_path+
    def remove_from_archive(archive_path, entry_name, format: DEFAULT_FORMAT)
      require_archive!(archive_path)
      resolved = resolve_archive_format(archive_path, format)
      handler = Omnizip::ArchiveHandler.for(resolved)
      # allowed: handler is a registered duck; missing remove_entry raises below
      unless handler.respond_to?(:remove_entry)
        raise Omnizip::UnsupportedFormatError,
              "Format #{resolved.inspect} does not support removing entries"
      end

      handler.remove_entry(archive_path, entry_name)
      archive_path
    end

    # Create a RAR archive (requires RAR license — see NotLicensedError).
    # rubocop:disable-next Naming/BlockForwarding, Style/ArgumentsForwarding -- Ruby 3.0 compatibility
    def create_rar(archive_path, **options, &block)
      options[:version] ||= 5
      Omnizip::Formats::Rar.create(archive_path, options, &block)
    end

    # Extension -> single-file compressor map. Each lambda takes
    # (input_path, output_path, options). These formats are streams,
    # not archives, so they bypass ArchiveHandler.
    # Extensions naming archive formats with a registered handler;
    # routed when the caller did not pass an explicit +format:+.
    ARCHIVE_FORMAT_EXTENSIONS = {
      ".zip" => :zip,
      ".tar" => :tar,
      ".7z" => :seven_zip,
    }.freeze

    # Extensions naming real formats this gem can READ but not write
    # through the convenience API. Writing them a ZIP under a foreign
    # name was silent corruption; failing truthfully is the only
    # honest behavior.
    READ_ONLY_FORMAT_EXTENSIONS = [".rar", ".iso", ".cpio"].freeze

    SINGLE_FILE_COMPRESSORS = {
      ".gz" => lambda do |input, output, options|
        Omnizip::Formats::Gzip.compress(input, output, options)
      end,
      ".bz2" => lambda do |input, output, options|
        Omnizip::Formats::Bzip2File.compress(input, output, options)
      end,
      ".xz" => lambda do |input, output, options|
        Omnizip::Formats::Xz.create(::File.binread(input), output, options)
      end,
      ".lzma" => lambda do |input, output, options|
        ::File.open(input, "rb") do |input_io|
          ::File.open(output, "wb") do |output_io|
            Omnizip::Formats::LzmaAlone.compress_stream(input_io, output_io,
                                                        options)
          end
        end
      end,
      ".lz" => lambda do |input, output, options|
        ::File.open(input, "rb") do |input_io|
          ::File.open(output, "wb") do |output_io|
            Omnizip::Formats::Lzip.compress_stream(input_io, output_io,
                                                   options)
          end
        end
      end,
    }.freeze

    # The single-file compressor matching the output extension, or nil.
    def single_file_handler(output_path)
      ext = ::File.extname(output_path).downcase
      SINGLE_FILE_COMPRESSORS[ext]
    end

    # Archive format for a path: an explicit +format+ wins unless it
    # is the default; otherwise the extension routes. Known-but-
    # unwritable extensions raise instead of receiving a mislabeled
    # ZIP.
    def resolve_archive_format(path, format)
      return format unless format == DEFAULT_FORMAT

      ext = ::File.extname(path).downcase
      routed = ARCHIVE_FORMAT_EXTENSIONS[ext]
      return routed if routed

      if READ_ONLY_FORMAT_EXTENSIONS.include?(ext)
        raise Omnizip::UnsupportedFormatError,
              "#{ext} archives cannot be written by the convenience " \
              "API (read-only support); use the format-specific reader"
      end

      DEFAULT_FORMAT
    end

    private

    def require_archive!(archive_path)
      return if ::File.exist?(archive_path)

      raise Errno::ENOENT, "Archive not found: #{archive_path}"
    end

    # Apply compression profile to options.
    def apply_profile(file_path, options)
      profile_spec = options.delete(:profile)
      return options unless profile_spec

      profile = case profile_spec
                when :auto
                  file_path ? Omnizip::Profile.detect(file_path) : Omnizip::Profile.get(:balanced)
                when Symbol
                  Omnizip::Profile.get(profile_spec) || Omnizip::Profile.get(:balanced)
                when Omnizip::Profile::CompressionProfile
                  profile_spec
                else
                  Omnizip::Profile.get(:balanced)
                end

      profile.apply_to(options)
    end

    def find_first_file(dir_path)
      Dir.foreach(dir_path) do |entry|
        next if [".", ".."].include?(entry)

        full_path = ::File.join(dir_path, entry)
        return full_path if ::File.file?(full_path)

        if ::File.directory?(full_path)
          result = find_first_file(full_path)
          return result if result
        end
      end
      nil
    end

    # Recursively add directory contents to an archive. The +archive+
    # argument is whatever the handler's +#create+ block yields (e.g.
    # +Omnizip::Zip::File+ or +Omnizip::Formats::Tar::Writer+) and must
    # respond to +#add(entry_name, src_path = nil)+.
    def add_directory_contents(archive, base_dir, relative_path, recursive: true)
      dir_path = ::File.join(base_dir, relative_path)

      Dir.foreach(dir_path) do |entry|
        next if [".", ".."].include?(entry)

        full_path = ::File.join(dir_path, entry)
        archive_path = if relative_path.empty?
                         entry
                       else
                         ::File.join(relative_path, entry)
                       end

        if ::File.directory?(full_path)
          dir_entry_name = archive_path.end_with?("/") ? archive_path : "#{archive_path}/"
          archive.add(dir_entry_name)
          if recursive
            add_directory_contents(archive, base_dir, archive_path,
                                   recursive: recursive)
          end
        else
          archive.add(archive_path, full_path)
        end
      end
    end
  end

  extend Convenience
end
