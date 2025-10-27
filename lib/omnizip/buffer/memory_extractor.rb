# frozen_string_literal: true

require "stringio"

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
          raise NotImplementedError, "7z format support coming in Phase 2"
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
          raise NotImplementedError, "7z format support coming in Phase 2"
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
          raise NotImplementedError, "7z format support coming in Phase 2"
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
          next unless name =~ pattern
          next if name.end_with?("/") # Skip directories

          content = extract_entry(name)
          result[name] = content if content
        end

        result
      end

      private

      # Detect archive format from magic bytes
      #
      # @return [Symbol] Detected format
      # @raise [Omnizip::FormatError] If format cannot be detected
      def detect_format
        magic = @buffer.read(4)
        @buffer.rewind

        case magic
        when "PK\x03\x04", "PK\x05\x06", "PK\x07\x08"
          # ZIP signatures: local file header, EOCD, data descriptor
          :zip
        when "7z\xBC\xAF"
          :seven_zip
        else
          raise Omnizip::FormatError,
                "Unknown archive format (magic: #{magic.inspect})"
        end
      end

      # Extract all entries from ZIP
      #
      # @param result [Hash] Hash to populate with entries
      def extract_all_zip(result)
        @buffer.rewind
        Omnizip::Zip::InputStream.open(@buffer) do |zis|
          while (entry = zis.get_next_entry)
            next if entry.directory?

            content = zis.read
            result[entry.name] = content
            @extracted_cache[entry.name] = content
          end
        end
      end

      # Extract single entry from ZIP
      #
      # @param name [String] Entry name
      # @return [String, nil] Entry content or nil if not found
      def extract_entry_zip(name)
        @buffer.rewind
        content = nil

        Omnizip::Zip::InputStream.open(@buffer) do |zis|
          while (entry = zis.get_next_entry)
            if entry.name == name
              content = zis.read unless entry.directory?
              break
            end
          end
        end

        content
      end

      # List all entry names from ZIP
      #
      # @param names [Array] Array to populate with names
      def list_entries_zip(names)
        @buffer.rewind

        Omnizip::Zip::InputStream.open(@buffer) do |zis|
          while (entry = zis.get_next_entry)
            names << entry.name
          end
        end
      end
    end
  end
end
