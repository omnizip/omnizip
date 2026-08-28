# frozen_string_literal: true

require "fileutils"

module Omnizip
  module Archive
    # Block argument (and return value) of +Archive.open+. Delegates
    # per operation to the resolved ArchiveHandler, which opens and
    # closes the underlying reader on every call — the session itself
    # holds no resources.
    class ReaderSession
      def initialize(handler, path, options = {})
        @handler = handler
        @path = path
        @options = options
      end

      # Archive metadata records (see Archive::Entry).
      def entries
        @handler.list(@path, details: true, **@options).map do |h|
          Entry.new(name: h[:name], size: h[:size], directory: h[:directory],
                    mtime: h[:mtime] || h[:time])
        end
      end

      def each_entry(&block)
        entries.each(&block)
      end

      # Contents of a single entry, without extraction.
      def read(entry_name)
        @handler.read_entry(@path, entry_name, **@options)
      end

      # Extract one entry to an explicit destination path.
      def extract(entry_name, dest_path)
        entry = entries.find { |e| e.name == entry_name }
        unless entry
          raise Errno::ENOENT, "Entry not found: #{entry_name}"
        end

        if entry.directory?
          ::FileUtils.mkdir_p(dest_path)
          return dest_path
        end

        ::FileUtils.mkdir_p(::File.dirname(dest_path))
        ::File.binwrite(dest_path, read(entry_name))
        dest_path
      end

      def extract_all(output_dir)
        @handler.extract_to(@path, output_dir, **@options)
      end

      # Extract every entry whose name matches +pattern+ under
      # +output_dir+, preserving archive-relative paths.
      def extract_matching(pattern, output_dir)
        ::FileUtils.mkdir_p(output_dir)
        entries.select do |e|
          !e.directory? && ::File.fnmatch?(pattern, e.name,
                                           ::File::FNM_PATHNAME)
        end.map { |e| extract(e.name, ::File.join(output_dir, e.name)) }
      end
    end
  end
end
