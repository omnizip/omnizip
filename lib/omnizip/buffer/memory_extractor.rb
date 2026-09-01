# frozen_string_literal: true

require "stringio"
require "tmpdir"

module Omnizip
  module Buffer
    # Extract archive contents to memory
    #
    # Provides efficient extraction of archive entries to Hash without
    # loading all files at once. Uses lazy evaluation where possible.
    #
    # @example Extract all files
    #   extractor = MemoryExtractor.new(zip_data)
    #   files = extractor.extract_all
    #   # => {"file1.txt" => "content1", "file2.txt" => "content2"}
    #
    # @example Extract single file
    #   extractor = MemoryExtractor.new(zip_data)
    #   content = extractor.extract_entry('file1.txt')
    #   # => "content1"
    class MemoryExtractor
      attr_reader :format

      # Initialize extractor
      #
      # @param data [String, StringIO] Archive data
      # @param format [Symbol, nil] Archive format (auto-detected if nil)
      #
      # @example Create extractor
      #   extractor = MemoryExtractor.new(zip_data)
      #   extractor = MemoryExtractor.new(zip_buffer, format: :zip)
      def initialize(data, format: nil)
        @buffer = data.is_a?(StringIO) ? data : StringIO.new(data.b)
        @format = format || detect_format
        @extracted_cache = {}
      end

      # Extract all entries to Hash
      #
      # @return [Hash<String, String>] Filename => content mapping
      #
      # @example Extract everything
      #   files = extractor.extract_all
      #   files.keys  # => ["file1.txt", "file2.txt", "dir/file3.txt"]
      def extract_all
        result = {}

        case @format
        when :zip
          extract_all_zip(result)
        when :seven_zip, :"7z"
          extract_all_seven_zip(result)
        else
          raise ArgumentError, "Unsupported format: #{@format}"
        end

        result
      end

      # Extract single entry by name
      #
      # @param name [String] Entry name to extract
      # @return [String, nil] Entry content or nil if not found
      #
      # @example Extract specific file
      #   content = extractor.extract_entry('readme.txt')
      #   # => "Hello World"
      def extract_entry(name)
        # Check cache first
        return @extracted_cache[name] if @extracted_cache.key?(name)

        # Extract from archive
        content = nil

        case @format
        when :zip
          content = extract_entry_zip(name)
        when :seven_zip, :"7z"
          content = extract_entry_seven_zip(name)
        else
          raise ArgumentError, "Unsupported format: #{@format}"
        end

        # Cache the result
        @extracted_cache[name] = content if content
        content
      end

      # List all entry names without extracting
      #
      # @return [Array<String>] Entry names
      #
      # @example List files
      #   extractor.list_entries
      #   # => ["file1.txt", "dir/", "dir/file2.txt"]
      def list_entries
        names = []

        case @format
        when :zip
          list_entries_zip(names)
        when :seven_zip, :"7z"
          SevenZipBridge.open(@buffer) { |archive| names.concat(archive.entry_names) }
        else
          raise ArgumentError, "Unsupported format: #{@format}"
        end

        names
      end

      # Check if entry exists in archive
      #
      # @param name [String] Entry name
      # @return [Boolean] True if entry exists
      #
      # @example Check existence
      #   extractor.entry_exists?('file.txt')  # => true
      def entry_exists?(name)
        list_entries.include?(name)
      end

      # Get total number of entries
      #
      # @return [Integer] Number of entries
      def entry_count
        list_entries.size
      end

      # Extract entries matching pattern
      #
      # @param pattern [Regexp, String] Pattern to match
      # @return [Hash<String, String>] Matching entries
      #
      # @example Extract by pattern
      #   extractor.extract_matching(/\.txt$/)
      #   # => {"file1.txt" => "content1", "file2.txt" => "content2"}
      def extract_matching(pattern)
        pattern = Regexp.new(pattern) if pattern.is_a?(String)
        result = {}

        list_entries.each do |name|
          next unless name&.match?(pattern)
          next if name.end_with?("/") # Skip directories

          content = extract_entry(name)
          result[name] = content if content
        end

        result
      end

      private

      # Delegate to the shared buffer-side sniffer
      #
      # @return [Symbol] Detected format
      # @raise [Omnizip::FormatError] If format cannot be detected
      def detect_format
        Omnizip::Buffer.detect_format(@buffer)
      end

      # The native ZIP reader parses from a path; spill the buffer to
      # a temporary file and yield a reader over it.
      def with_zip_reader
        @buffer.rewind
        Dir.mktmpdir("omnizip_extractor_zip") do |tmp|
          path = File.join(tmp, "buffer.zip")
          File.binwrite(path, @buffer.read)
          yield Omnizip::Formats::Zip::Reader.new(path)
        end
      end

      # Extract all entries from ZIP through the native reader
      #
      # @param result [Hash] Hash to populate with entries
      def extract_all_zip(result)
        with_zip_reader do |reader|
          reader.entries.each do |entry|
            next if entry.directory?

            content = reader.read_entry(entry.filename)
            result[entry.filename] = content
            @extracted_cache[entry.filename] = content
          end
        end
      end

      # Extract every file entry from 7z
      #
      # @param result [Hash] Hash to populate with entries
      def extract_all_seven_zip(result)
        @buffer.rewind
        SevenZipBridge.open(@buffer) do |archive|
          archive.extract_all_to_memory.each do |name, content|
            result[name] = content
            @extracted_cache[name] = content
          end
        end
      end

      # Extract single entry from 7z
      #
      # @param name [String] Entry name
      # @return [String, nil] Entry content or nil if not found
      def extract_entry_seven_zip(name)
        @buffer.rewind
        SevenZipBridge.open(@buffer) do |archive|
          archive.read_entry(name)
        end
      end

      # Extract single entry from ZIP through the native reader
      #
      # @param name [String] Entry name
      # @return [String, nil] Entry content or nil if not found
      def extract_entry_zip(name)
        with_zip_reader do |reader|
          entry = reader.entries.find { |e| e.filename == name }
          reader.read_entry(name) if entry && !entry.directory?
        end
      end

      # List all entry names from ZIP through the native reader
      #
      # @param names [Array] Array to populate with names
      def list_entries_zip(names)
        with_zip_reader do |reader|
          reader.entries.each { |entry| names << entry.filename }
        end
      end
    end
  end
end
