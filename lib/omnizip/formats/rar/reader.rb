# frozen_string_literal: true

require "fileutils"
require "stringio"
require "zlib"

module Omnizip
  module Formats
    module Rar
      # RAR archive reader
      # Provides read-only access to RAR archives (single and multi-volume)
      class Reader
        include Omnizip::Formats::Rar::Constants

        attr_reader :file_path, :header, :archive_info,
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
          @use_native = true # Prefer native decompression
          @opened = false
        end

        # Open and parse RAR archive
        #
        # @raise [RuntimeError] if file cannot be opened or parsed
        def open
          File.open(@file_path, "rb") do |io|
            parse_archive(io)
          end
          @opened = true
          self
        end

        # All entries, parsing on first use — a Reader is always
        # usable; #open remains for eager loading
        #
        # @return [Array<Models::RarEntry>] File entries
        def entries
          ensure_open
          @entries
        end

        # List all files in archive
        #
        # @return [Array<Models::RarEntry>] File entries
        def list_files
          entries
        end

        # Extract file to output path
        #
        # @param entry_name [String] File name to extract
        # @param output_path [String] Destination path
        # @param password [String, nil] Optional password
        # @raise [RuntimeError] if entry not found or extraction fails
        def extract_entry(entry_name, output_path, password: nil)
          ensure_open
          entry = @entries.find { |e| e.name == entry_name }
          raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

          # Create directory if needed
          FileUtils.mkdir_p(File.dirname(output_path))

          # Extract file
          if entry.directory?
            FileUtils.mkdir_p(output_path)
          else
            # Try native decompression first, fall back to external
            if @use_native && native_decompression_available?(entry)
              extract_entry_native(entry, output_path)
            else
              extract_entry_external(entry_name, output_path, password)
            end

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
          ensure_open
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

        # Parse the archive once, on demand
        def ensure_open
          open unless @opened
        end

        # Parse RAR archive structure
        #
        # @param io [IO] Input stream
        def parse_archive(io)
          # Read and validate header
          @header = Header.read(io)
          raise Omnizip::InvalidArchiveError, "Invalid RAR archive" unless @header.valid?

          # Update archive info
          @archive_info.version = @header.version
          @archive_info.flags = @header.flags
          @archive_info.is_multi_volume = @header.is_multi_volume
          @archive_info.volumes = @volume_manager.volumes

          # Detect recovery records
          detect_recovery_records

          # Parse entries natively first (full metadata: sizes,
          # directory flags); fall back to the external decompressor
          # when native parsing yields nothing (e.g. encrypted
          # headers).
          parse_entries_from_header
          parse_entries_with_decompressor if @entries.empty?
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
        # Falls back to native parser if decompressor fails or unavailable
        def parse_entries_with_decompressor
          unless Decompressor.available?
            # If decompressor not available, create minimal entries from header
            parse_entries_from_header
            return
          end

          # Try to list archive contents with external tool
          begin
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
          rescue StandardError => e
            # Fall back to native parser if external decompressor fails
            warn "External decompressor failed: #{e.message}"
            warn "Falling back to native block parser"
            parse_entries_from_header
          end
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

        # Check if native decompression is available for entry
        #
        # @param entry [Models::RarEntry] File entry
        # @return [Boolean] true if native decompression supported
        def native_decompression_available?(entry)
          # Native decompression only for RAR4 for now
          return false unless @header.version == 4

          !entry.nil? && !entry.method.nil?
        end

        # Extract entry using native decompression
        #
        # @param entry [Models::RarEntry] File entry
        # @param output_path [String] Destination path
        def extract_entry_native(entry, output_path)
          compressed_data = read_compressed_data(entry)
          method = entry.method || 0x30

          output = StringIO.new(+"")
          Compression::Dispatcher.decompress(method, compressed_data, output)

          # The native LZ/PPMd decoders understand Omnizip's own
          # encoder output, not official RAR streams — without this
          # check, real WinRAR archives would silently extract as
          # garbage. The header CRC is authoritative: on mismatch,
          # fall back to unrar.
          data = output.string
          if entry.crc && Zlib.crc32(data) != entry.crc
            raise Compression::Dispatcher::DecompressionError,
                  "CRC mismatch for #{entry.name}"
          end

          File.binwrite(output_path, data)
        rescue StandardError => e
          # Fall back to external decompressor on error
          warn "Native decompression failed for #{entry.name}: #{e.message}"
          warn "Falling back to external decompressor"
          extract_entry_external(entry.name, output_path, nil)
        end

        # Extract entry using external decompressor
        #
        # @param entry_name [String] Entry name
        # @param output_path [String] Destination path
        # @param password [String, nil] Optional password
        def extract_entry_external(entry_name, output_path, password)
          base_path = @volume_manager.first_volume&.path || @file_path
          Decompressor.extract_entry(base_path, entry_name,
                                     output_path, password: password)
        end

        # Read compressed data for entry
        #
        # @param entry [Models::RarEntry] File entry
        # @return [StringIO] Compressed data stream
        def read_compressed_data(entry)
          # The parser records each entry's data offset, so native
          # extraction is a single seek + read
          if entry.data_offset && entry.compressed_size
            File.open(@file_path, "rb") do |io|
              io.seek(entry.data_offset)
              return StringIO.new(io.read(entry.compressed_size) || "")
            end
          end

          # Fallback for entries parsed without offsets (e.g. by older
          # parsers): walk the blocks to locate the entry
          File.open(@file_path, "rb") do |io|
            Header.read(io)

            parser = BlockParser.new(@header.version)

            loop do
              block_start = io.pos
              break if io.eof?

              crc_bytes = io.read(2)
              break unless crc_bytes

              type_byte = io.read(1)
              break unless type_byte

              head_type = type_byte.ord

              break if head_type == BLOCK_ENDARC

              io.seek(block_start)

              unless head_type == BLOCK_FILE
                io.read(2) # CRC
                io.read(1) # TYPE
                io.read(2) # FLAGS
                size = io.read(2)&.unpack1("v") || 0

                # 7 bytes consumed (CRC/TYPE/FLAGS/SIZE); skip the rest
                remaining = size - 7
                io.read(remaining) if remaining.positive?
                next
              end

              test_entry = parser.parse_file_block(io)

              if test_entry && test_entry.name == entry.name
                data_start = io.pos - entry.compressed_size

                io.seek(data_start)
                return StringIO.new(io.read(entry.compressed_size) || "")
              end
            end
          end

          StringIO.new("")
        end
      end
    end
  end
end
