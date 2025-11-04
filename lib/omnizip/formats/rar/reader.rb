# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "block_parser"
require_relative "decompressor"
require_relative "volume_manager"
require_relative "recovery_record"
require_relative "models/rar_entry"
require_relative "models/rar_archive"
require "fileutils"

module Omnizip
  module Formats
    module Rar
      # RAR archive reader
      # Provides read-only access to RAR archives (single and multi-volume)
      class Reader
        include Constants

        attr_reader :file_path, :header, :entries, :archive_info,
                    :volume_manager

        # Initialize reader with file path
        #
        # @param file_path [String] Path to RAR file
        def initialize(file_path)
          @file_path = file_path
          @header = nil
          @entries = []
          @archive_info = Models::RarArchive.new(file_path)
          @volume_manager = VolumeManager.new(file_path)
        end

        # Open and parse RAR archive
        #
        # @raise [RuntimeError] if file cannot be opened or parsed
        def open
          File.open(@file_path, "rb") do |io|
            parse_archive(io)
          end
          self
        end

        # List all files in archive
        #
        # @return [Array<Models::RarEntry>] File entries
        def list_files
          @entries
        end

        # Extract file to output path
        #
        # @param entry_name [String] File name to extract
        # @param output_path [String] Destination path
        # @param password [String, nil] Optional password
        # @raise [RuntimeError] if entry not found or extraction fails
        def extract_entry(entry_name, output_path, password: nil)
          entry = @entries.find { |e| e.name == entry_name }
          raise "Entry not found: #{entry_name}" unless entry

          # Create directory if needed
          FileUtils.mkdir_p(File.dirname(output_path))

          # Extract file
          if entry.directory?
            FileUtils.mkdir_p(output_path)
          else
            # Use decompressor to extract
            base_path = @volume_manager.first_volume&.path || @file_path
            Decompressor.extract_entry(base_path, entry_name,
                                       output_path, password: password)

            # Set timestamp if available
            File.utime(entry.mtime, entry.mtime, output_path) if entry.mtime
          end
        end

        # Extract all files to directory
        #
        # @param output_dir [String] Destination directory
        # @param password [String, nil] Optional password
        # @raise [RuntimeError] on extraction error
        def extract_all(output_dir, password: nil)
          FileUtils.mkdir_p(output_dir)

          # Use decompressor to extract all
          base_path = @volume_manager.first_volume&.path || @file_path
          Decompressor.extract(base_path, output_dir, password: password)

          # Set timestamps for extracted files
          @entries.each do |entry|
            next unless entry.mtime

            output_path = File.join(output_dir, entry.name)
            next unless File.exist?(output_path)

            File.utime(entry.mtime, entry.mtime, output_path)
          end
        end

        # Check if archive is valid RAR format
        #
        # @return [Boolean] true if valid
        def valid?
          !@header.nil? && @header.valid?
        end

        # Get volumes in multi-volume archive
        #
        # @return [Array<String>] Volume paths
        def volumes
          @volume_manager.volume_paths
        end

        # Get total number of volumes
        #
        # @return [Integer] Number of volumes
        def total_volumes
          @volume_manager.volume_count
        end

        # Check if multi-volume archive
        #
        # @return [Boolean] true if multi-volume
        def multi_volume?
          @volume_manager.multi_volume? || @header&.is_multi_volume
        end

        private

        # Parse RAR archive structure
        #
        # @param io [IO] Input stream
        def parse_archive(io)
          # Read and validate header
          @header = Header.read(io)
          raise "Invalid RAR archive" unless @header.valid?

          # Update archive info
          @archive_info.version = @header.version
          @archive_info.flags = @header.flags
          @archive_info.is_multi_volume = @header.is_multi_volume
          @archive_info.volumes = @volume_manager.volumes

          # Detect recovery records
          detect_recovery_records

          # Parse entries using decompressor
          parse_entries_with_decompressor
        end

        # Detect recovery records in archive
        def detect_recovery_records
          recovery = RecoveryRecord.new(@header.version)

          # Check for integrated recovery
          File.open(@file_path, "rb") do |io|
            recovery.parse_from_archive(io, @header.flags)
          end

          # Check for external .rev files
          rev_files = recovery.detect_external_files(@file_path)
          recovery.load_external_files(rev_files) if rev_files.any?

          # Update archive info
          @archive_info.has_recovery = recovery.available?
          @archive_info.recovery_percent = recovery.protection_percent
          @archive_info.recovery_files = recovery.external_files
        end

        # Parse entries using decompressor
        #
        # This uses the external decompressor to list archive contents
        # since parsing RAR compressed data requires proprietary algorithms
        def parse_entries_with_decompressor
          unless Decompressor.available?
            # If decompressor not available, create minimal entries from header
            parse_entries_from_header
            return
          end

          # List archive contents
          entry_info = Decompressor.list(@file_path)
          entry_info.each do |info|
            entry = Models::RarEntry.new
            entry.name = info[:name]
            entry.size = info[:size]
            entry.compressed_size = info[:compressed_size]
            entry.is_dir = info[:is_dir]
            entry.mtime = info[:mtime]
            entry.version = @header.version

            @entries << entry
            @archive_info.total_size += entry.size
            @archive_info.compressed_size += entry.compressed_size
          end

          @archive_info.entries = @entries
        end

        # Parse entries from header (fallback when decompressor unavailable)
        #
        # This provides basic information but cannot extract files
        def parse_entries_from_header
          # Reset to after header
          File.open(@file_path, "rb") do |io|
            Header.read(io) # Skip header

            # Try to parse file blocks
            parser = BlockParser.new(@header.version)

            loop do
              pos = io.pos
              break if io.eof?

              begin
                entry = parser.parse_file_block(io)
                break unless entry

                @entries << entry
                @archive_info.total_size += entry.size
                @archive_info.compressed_size += entry.compressed_size
              rescue StandardError => e
                warn "Failed to parse block at #{pos}: #{e.message}"
                break
              end
            end
          end

          @archive_info.entries = @entries
        end
      end
    end
  end
end
