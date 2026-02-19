# frozen_string_literal: true

require_relative "rar/constants"
require_relative "rar/header"
require_relative "rar/block_parser"
require_relative "rar/decompressor"
require_relative "rar/volume_manager"
require_relative "rar/recovery_record"
require_relative "rar/parity_handler"
require_relative "rar/archive_verifier"
require_relative "rar/archive_repairer"
require_relative "rar/reader"
require_relative "rar/writer"
require_relative "rar/models/rar_entry"
require_relative "rar/models/rar_volume"
require_relative "rar/models/rar_archive"

# RAR5 format support (pure Ruby)
require_relative "rar/rar5/vint"
require_relative "rar/rar5/crc32"
require_relative "rar/rar5/header"
require_relative "rar/rar5/writer"

# RAR compression layer (native pure Ruby implementation)
require_relative "rar/compression/bit_stream"
require_relative "rar/compression/ppmd/context"
require_relative "rar/compression/ppmd/decoder"
require_relative "rar/compression/lz77_huffman/sliding_window"
require_relative "rar/compression/lz77_huffman/huffman_coder"
require_relative "rar/compression/lz77_huffman/decoder"
require_relative "rar/compression/dispatcher"

module Omnizip
  module Formats
    # RAR archive format support
    # Provides read-only access to RAR archives (single and multi-volume)
    #
    # This module implements RAR archive format support:
    # - Format signature validation (RAR4 and RAR5)
    # - Archive structure parsing
    # - File listing
    # - File extraction (requires unrar gem or system command)
    # - Multi-volume archive support
    #
    # Note: RAR compression is proprietary, so this implementation
    # is read-only and requires external decompression tools.
    module Rar
      class << self
        # Check if RAR extraction is available
        #
        # @return [Boolean] true if unrar available
        def available?
          Decompressor.available?
        end

        # Get decompressor information
        #
        # @return [Hash] Decompressor type and version
        def decompressor_info
          Decompressor.info
        end

        # Check if RAR creation is available
        #
        # @return [Boolean] true for pure Ruby writer
        def writer_available?
          Writer.available?
        end

        # Get RAR writer information
        #
        # @return [Hash] Writer type and version
        def writer_info
          Writer.info
        end

        # Create RAR archive (requires licensed WinRAR for RAR4, pure Ruby for RAR5)
        #
        # @param path [String] Output RAR file path
        # @param options [Hash] Creation options
        # @option options [Integer] :version RAR version (4 or 5, default: 4)
        # @option options [Symbol] :compression For RAR5: :store, :lzma, :auto (default: :store)
        # @option options [Integer] :level For RAR5: LZMA level 1-5 (default: 3)
        # @option options [Boolean] :include_mtime Include modification time (RAR5 only)
        # @option options [Boolean] :include_crc32 Include CRC32 checksum (RAR5 only)
        # @yield [Writer] Writer instance
        # @return [String] Path to created archive
        #
        # @example Create RAR4 archive (requires WinRAR)
        #   Omnizip::Formats::Rar.create('archive.rar') do |rar|
        #     rar.add_file('document.pdf')
        #     rar.add_directory('photos/')
        #   end
        #
        # @example Create RAR5 archive (pure Ruby)
        #   Omnizip::Formats::Rar.create('archive.rar', version: 5) do |rar|
        #     rar.add_file('document.pdf')
        #   end
        #
        # @example Create RAR5 with LZMA compression
        #   Omnizip::Formats::Rar.create('archive.rar',
        #     version: 5,
        #     compression: :lzma,
        #     level: 5,
        #     include_mtime: true,
        #     include_crc32: true
        #   ) do |rar|
        #     rar.add_file('data.txt')
        #   end
        def create(path, options = {})
          version = options.delete(:version) || 4

          writer = if version == 5
                     # Use pure Ruby RAR5 writer
                     Rar5::Writer.new(path, options)
                   else
                     # Use RAR4 writer (requires WinRAR)
                     Writer.new(path, options)
                   end

          yield writer if block_given?

          writer.write
        end

        # Open RAR archive
        #
        # @param path [String] Path to RAR file
        # @yield [Reader] Archive reader
        # @return [Reader] Archive reader if no block given
        def open(path)
          reader = Reader.new(path)
          reader.open

          if block_given?

            yield reader

          # Reader doesn't need explicit closing

          else
            reader
          end
        end

        # List RAR archive contents
        #
        # @param path [String] Path to RAR file
        # @return [Array<Models::RarEntry>] File entries
        def list(path)
          open(path, &:list_files)
        end

        # Extract RAR archive to directory
        #
        # @param path [String] Path to RAR file
        # @param dest [String] Destination directory
        # @param password [String, nil] Optional password
        def extract(path, dest, password: nil)
          open(path) do |rar|
            rar.extract_all(dest, password: password)
          end
        end

        # Get archive information
        #
        # @param path [String] Path to RAR file
        # @return [Models::RarArchive] Archive information
        def info(path)
          open(path, &:archive_info)
        end

        # Verify RAR archive integrity
        #
        # @param path [String] Path to RAR file
        # @param use_recovery [Boolean] Use recovery records
        # @return [ArchiveVerifier::VerificationResult] Verification results
        def verify(path, use_recovery: true)
          verifier = ArchiveVerifier.new(path)
          verifier.verify(use_recovery: use_recovery)
        end

        # Repair corrupted RAR archive
        #
        # @param input_path [String] Path to corrupted RAR file
        # @param output_path [String] Path for repaired archive
        # @param options [Hash] Repair options
        # @return [ArchiveRepairer::RepairResult] Repair results
        def repair(input_path, output_path, options = {})
          repairer = ArchiveRepairer.new
          repairer.repair(input_path, output_path, options)
        end

        # Auto-register RAR format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".rar", Reader)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Rar.register!
