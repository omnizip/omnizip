# frozen_string_literal: true

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
      # Nested classes - autoloaded
      autoload :Constants, "omnizip/formats/seven_zip/constants"
      autoload :Header, "omnizip/formats/seven_zip/header"
      autoload :Parser, "omnizip/formats/seven_zip/parser"
      autoload :Reader, "omnizip/formats/seven_zip/reader"
      autoload :Writer, "omnizip/formats/seven_zip/writer"
      autoload :CoderChain, "omnizip/formats/seven_zip/coder_chain"
      autoload :StreamDecompressor,
               "omnizip/formats/seven_zip/stream_decompressor"
      autoload :StreamCompressor, "omnizip/formats/seven_zip/stream_compressor"
      autoload :FileCollector, "omnizip/formats/seven_zip/file_collector"
      autoload :HeaderWriter, "omnizip/formats/seven_zip/header_writer"
      autoload :SplitArchiveReader,
               "omnizip/formats/seven_zip/split_archive_reader"
      autoload :SplitArchiveWriter,
               "omnizip/formats/seven_zip/split_archive_writer"
      autoload :HeaderEncryptor, "omnizip/formats/seven_zip/header_encryptor"
      autoload :EncryptedHeader, "omnizip/formats/seven_zip/encrypted_header"
      autoload :EncodedHeader, "omnizip/formats/seven_zip/encoded_header"
      autoload :Bcj2StreamDecompressor,
               "omnizip/formats/seven_zip/bcj2_stream_decompressor"
      module Models
        autoload :StreamInfo, "omnizip/formats/seven_zip/models/stream_info"
        autoload :FileEntry, "omnizip/formats/seven_zip/models/file_entry"
        autoload :Folder, "omnizip/formats/seven_zip/models/folder"
        autoload :CoderInfo, "omnizip/formats/seven_zip/models/coder_info"
      end
      # Add autoload for Models namespace itself
      autoload :Models, "omnizip/formats/seven_zip/models"

      # Cross-namespace dependencies - autoloaded
      autoload :Crc32, "omnizip/checksums/crc32"
      autoload :LZMA2, "omnizip/algorithms/lzma2"
      autoload :AlgorithmRegistry, "omnizip/algorithm_registry"
      autoload :FilterRegistry, "omnizip/filter_registry"
      autoload :FilterPipeline, "omnizip/filter_pipeline"
      autoload :Bcj2Decoder, "omnizip/filters/bcj2/decoder"
      autoload :Bcj2StreamData, "omnizip/filters/bcj2/stream_data"

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
        data.index(signature)
      end

      # Auto-register .7z format when loaded
      def self.register!
        require "omnizip/format_registry"
        FormatRegistry.register(".7z", Reader)
      end
    end
  end
end
