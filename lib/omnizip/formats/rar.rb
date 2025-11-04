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
require_relative "rar/license_validator"
require_relative "rar/external_writer"
require_relative "rar/models/rar_entry"
require_relative "rar/models/rar_volume"
require_relative "rar/models/rar_archive"

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
        # @return [Boolean] true if WinRAR available
        def writer_available?
          ExternalWriter.available?
        end

        # Get RAR writer information
        #
        # @return [Hash] Writer type and version
        def writer_info
          ExternalWriter.info
        end

        # Create RAR archive (requires licensed WinRAR)
        #
        # @param path [String] Output RAR file path
        # @param options [Hash] Creation options
        # @yield [ExternalWriter] Writer instance
        # @return [String] Path to created archive
        # @raise [NotLicensedError] if WinRAR license not confirmed
        # @raise [RarNotAvailableError] if WinRAR not installed
        #
        # @example Create RAR archive
        #   Omnizip::Formats::Rar.create('archive.rar') do |rar|
        #     rar.add_file('document.pdf')
        #     rar.add_directory('photos/')
        #   end
        #
        # @example With compression options
        #   Omnizip::Formats::Rar.create('archive.rar',
        #     compression: :best,
        #     solid: true,
        #     recovery: 5
        #   ) do |rar|
        #     rar.add_directory('data/')
        #   end
        def create(path, options = {})
          writer = ExternalWriter.new(path, options)

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
