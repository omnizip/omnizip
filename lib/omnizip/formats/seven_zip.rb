# frozen_string_literal: true

require_relative "seven_zip/constants"
require_relative "seven_zip/header"
require_relative "seven_zip/parser"
require_relative "seven_zip/reader"
require_relative "seven_zip/writer"
require_relative "seven_zip/coder_chain"
require_relative "seven_zip/stream_decompressor"
require_relative "seven_zip/stream_compressor"
require_relative "seven_zip/file_collector"
require_relative "seven_zip/header_writer"
require_relative "seven_zip/split_archive_reader"
require_relative "seven_zip/split_archive_writer"
require_relative "../models/split_options"

module Omnizip
  module Formats
    # .7z archive format support
    # Provides read and write access to 7-Zip archives
    #
    # This module implements the .7z archive format specification,
    # supporting:
    # - Format signature and header validation
    # - Archive structure parsing
    # - File extraction
    # - Archive creation
    # - Split archives (multi-volume)
    module SevenZip
      # Create a new .7z archive
      #
      # @param path [String] Output path
      # @param options [Hash] Compression options
      # @option options [Integer] :volume_size Volume size for split archives
      # @option options [String] :password Password for header encryption
      # @option options [Boolean] :encrypt_headers Encrypt archive headers
      # @yield [writer] Block for adding files
      # @yieldparam writer [Writer] Archive writer
      def self.create(path, options = {})
        writer = Writer.new(path, options)
        yield writer if block_given?
        writer.write
        writer
      end

      # Create a split .7z archive
      #
      # @param path [String] Base path (e.g., "backup.7z.001")
      # @param split_options [Models::SplitOptions] Split configuration
      # @param options [Hash] Compression options
      # @yield [writer] Block for adding files
      # @yieldparam writer [SplitArchiveWriter] Archive writer
      def self.create_split(path, split_options, options = {})
        writer = SplitArchiveWriter.new(path, options, split_options)
        yield writer if block_given?
        writer.write
        writer
      end

      # Open existing .7z archive
      #
      # @param path [String] Archive path
      # @param options [Hash] Reader options
      # @option options [String] :password Password for encrypted headers
      # @yield [reader] Block for reading archive
      # @yieldparam reader [Reader] Archive reader
      # @return [Reader] Archive reader
      def self.open(path, options = {})
        reader = Reader.new(path, options)
        reader.open

        if block_given?
          begin
            yield reader
          ensure
            reader.split_reader&.close if reader.respond_to?(:split_reader)
          end
        end

        reader
      end

      # Search for embedded .7z archive in self-extracting executable
      #
      # @param path [String] Path to potential self-extracting archive
      # @return [Integer, nil] Offset of embedded 7z signature, or nil if not found
      def self.search_embedded(path)
        data = File.binread(path)
        signature = Constants::SIGNATURE
        offset = data.index(signature)
        offset
      end

      # Auto-register .7z format when loaded
      def self.register!
        require_relative "../format_registry"
        FormatRegistry.register(".7z", Reader)
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::SevenZip.register!
