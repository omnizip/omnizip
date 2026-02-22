# frozen_string_literal: true

require "stringio"
require_relative "buffer/memory_archive"
require_relative "buffer/memory_extractor"

module Omnizip
  # In-memory archive operations without filesystem I/O
  #
  # This module provides methods for creating and reading archives
  # entirely in memory using StringIO, enabling web applications,
  # testing, and API responses without temporary files.
  #
  # @example Create archive in memory
  #   zip_data = Omnizip::Buffer.create(:zip) do |archive|
  #     archive.add('readme.txt', 'Hello World')
  #     archive.add('data.json', '{"key": "value"}')
  #   end
  #   # => Returns StringIO with complete ZIP archive
  #
  # @example Extract from memory
  #   contents = Omnizip::Buffer.extract_to_memory(zip_data)
  #   # => {"readme.txt" => "Hello World", "data.json" => '{"key": "value"}'}
  #
  # @example From Hash
  #   archive_data = {
  #     'file1.txt' => 'content1',
  #     'file2.txt' => 'content2'
  #   }
  #   zip_buffer = Omnizip::Buffer.create_from_hash(archive_data, :zip)
  module Buffer
    class << self
      # Create archive in memory
      #
      # @param format [Symbol] Archive format (:zip, :seven_zip)
      # @param options [Hash] Format-specific options
      # @yield [archive] Block to populate archive
      # @yieldparam archive [MemoryArchive] Archive object to add entries to
      # @return [StringIO] Complete archive in memory, rewound to start
      #
      # @example Create ZIP in memory
      #   buffer = Omnizip::Buffer.create(:zip) do |archive|
      #     archive.add('file.txt', 'content')
      #     archive.add('dir/file2.txt', 'more content')
      #   end
      #   File.binwrite('output.zip', buffer.string)
      # rubocop:disable Naming/BlockForwarding, Style/ArgumentsForwarding -- Ruby 3.0 compatibility
      def create(format = :zip, **options, &block)
        buffer = StringIO.new(String.new(encoding: Encoding::BINARY))

        case format
        when :zip
          create_zip(buffer, options, &block)
        when :seven_zip, :"7z"
          raise NotImplementedError, "7z format support coming in Phase 2"
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end

        buffer.tap(&:rewind)
      end
      # rubocop:enable Naming/BlockForwarding, Style/ArgumentsForwarding

      # Open archive from memory
      #
      # @param data [String, StringIO] Archive data
      # @param format [Symbol, nil] Archive format (auto-detected if nil)
      # @yield [archive] Block to read from archive
      # @yieldparam archive [MemoryArchive] Archive object to read entries from
      # @return [MemoryArchive, Object] Archive object or block return value
      #
      # @example Read entries
      #   Omnizip::Buffer.open(zip_data) do |archive|
      #     archive.each_entry do |entry|
      #       puts "#{entry.name}: #{entry.size} bytes"
      #     end
      #   end
      def open(data, format: nil, &block)
        buffer = data.is_a?(StringIO) ? data : StringIO.new(data.b)
        format ||= detect_format(buffer)

        case format
        when :zip
          open_zip(buffer, &block)
        when :seven_zip, :"7z"
          raise NotImplementedError, "7z format support coming in Phase 2"
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      # Extract all entries to memory
      #
      # @param data [String, StringIO] Archive data
      # @param format [Symbol, nil] Archive format (auto-detected if nil)
      # @return [Hash<String, String>] Filename => content mapping
      #
      # @example Extract to Hash
      #   files = Omnizip::Buffer.extract_to_memory(zip_data)
      #   files.each do |name, content|
      #     puts "#{name}: #{content.bytesize} bytes"
      #   end
      def extract_to_memory(data, format: nil)
        extractor = Buffer::MemoryExtractor.new(data, format: format)
        extractor.extract_all
      end

      # Create archive from Hash of filename => content
      #
      # @param hash [Hash<String, String>] Filename => content mapping
      # @param format [Symbol] Archive format
      # @param options [Hash] Format-specific options
      # @return [StringIO] Complete archive in memory
      #
      # @example Create from Hash
      #   data = {'file1.txt' => 'content1', 'file2.txt' => 'content2'}
      #   zip = Omnizip::Buffer.create_from_hash(data, :zip)
      def create_from_hash(hash, format = :zip, **options)
        create(format, **options) do |archive|
          hash.each do |name, content|
            archive.add(name, content)
          end
        end
      end

      private

      # Detect archive format from magic bytes
      #
      # @param buffer [StringIO] Buffer containing archive data
      # @return [Symbol] Detected format
      # @raise [Omnizip::FormatError] If format cannot be detected
      def detect_format(buffer)
        magic = buffer.read(4)
        buffer.rewind

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

      # Create ZIP archive in buffer
      #
      # @param buffer [StringIO] Buffer to write to
      # @param options [Hash] ZIP-specific options
      # @yield [archive] Block to populate archive
      def create_zip(buffer, _options, &block)
        Omnizip::Zip::OutputStream.open(buffer) do |zos|
          archive = Buffer::MemoryArchive.new(zos, :zip)
          block&.call(archive)
        end
      end

      # Open ZIP archive from buffer
      #
      # @param buffer [StringIO] Buffer containing ZIP data
      # @yield [archive] Block to read from archive
      # @return [MemoryArchive, Object] Archive or block return value
      def open_zip(buffer, &block)
        result = nil
        Omnizip::Zip::InputStream.open(buffer) do |zis|
          archive = Buffer::MemoryArchive.new(zis, :zip)
          result = block ? yield(archive) : archive
        end
        result
      end
    end
  end
end
