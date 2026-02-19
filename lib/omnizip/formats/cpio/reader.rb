# frozen_string_literal: true

require "fileutils"
require_relative "constants"
require_relative "entry"

module Omnizip
  module Formats
    module Cpio
      # CPIO archive reader
      #
      # Reads CPIO archives in newc, CRC, ODC, and binary formats.
      # Automatically detects format from magic number.
      #
      # @example Read CPIO archive
      #   reader = Cpio::Reader.new('archive.cpio')
      #   reader.open
      #   reader.entries.each { |entry| puts entry.name }
      #
      # @example Extract CPIO archive
      #   reader = Cpio::Reader.new('archive.cpio')
      #   reader.open
      #   reader.extract_all('output/')
      class Reader
        include Constants

        # @return [String] Archive file path
        attr_reader :file_path

        # @return [Array<Entry>] Parsed entries
        attr_reader :entries

        # @return [Symbol, nil] Detected format
        attr_reader :format

        # Initialize CPIO reader
        #
        # @param file_path [String] Path to CPIO archive
        def initialize(file_path)
          @file_path = file_path
          @entries = []
          @format = nil
        end

        # Open and parse CPIO archive
        #
        # @raise [RuntimeError] if file cannot be opened or parsed
        def open
          File.open(@file_path, "rb") do |io|
            parse_archive(io)
          end
          self
        end

        # List all entries
        #
        # @return [Array<Entry>] All entries except trailer
        def list
          @entries.reject(&:trailer?)
        end

        # Extract entry to output path
        #
        # @param entry_name [String] Entry name to extract
        # @param output_path [String] Destination path
        # @raise [RuntimeError] if entry not found
        def extract_entry(entry_name, output_path)
          entry = @entries.find { |e| e.name == entry_name }
          raise "Entry not found: #{entry_name}" unless entry

          extract_single_entry(entry, output_path)
        end

        # Extract all entries to directory
        #
        # @param output_dir [String] Output directory
        def extract_all(output_dir)
          FileUtils.mkdir_p(output_dir)

          @entries.each do |entry|
            next if entry.trailer?

            output_path = File.join(output_dir, entry.name)
            extract_single_entry(entry, output_path)
          end
        end

        # Get archive format
        #
        # @return [String] Human-readable format name
        def format_name
          case @format
          when :newc then "CPIO newc (SVR4)"
          when :crc then "CPIO newc with CRC"
          when :odc then "CPIO ODC (portable)"
          when :binary then "CPIO binary (old)"
          else "Unknown"
          end
        end

        private

        # Parse archive contents
        #
        # @param io [IO] Input stream
        def parse_archive(io)
          while !io.eof?
            begin
              entry = Entry.parse(io, format: @format)

              # Detect format from first entry
              @format ||= Entry.detect_format(entry.magic)

              # Add entry (including trailer)
              @entries << entry

              # Stop at trailer
              break if entry.trailer?
            rescue StandardError => e
              warn "Failed to parse CPIO entry: #{e.message}"
              break
            end
          end
        end

        # Extract single entry
        #
        # @param entry [Entry] Entry to extract
        # @param output_path [String] Destination path
        def extract_single_entry(entry, output_path)
          if entry.directory?
            extract_directory(entry, output_path)
          elsif entry.symlink?
            extract_symlink(entry, output_path)
          elsif entry.device?
            # Skip device files (require root privileges)
            warn "Skipping device file: #{entry.name}"
          else
            extract_file(entry, output_path)
          end

          # Set permissions and timestamps
          set_entry_attributes(entry, output_path) unless entry.symlink?
        end

        # Extract directory
        #
        # @param entry [Entry] Directory entry
        # @param output_path [String] Destination path
        def extract_directory(_entry, output_path)
          FileUtils.mkdir_p(output_path)
        end

        # Extract regular file
        #
        # @param entry [Entry] File entry
        # @param output_path [String] Destination path
        def extract_file(entry, output_path)
          FileUtils.mkdir_p(File.dirname(output_path))
          File.binwrite(output_path, entry.data)
        end

        # Extract symbolic link
        #
        # @param entry [Entry] Symlink entry
        # @param output_path [String] Destination path
        def extract_symlink(entry, output_path)
          FileUtils.mkdir_p(File.dirname(output_path))

          # Remove existing file/link if present
          File.unlink(output_path) if File.exist?(output_path) || File.symlink?(output_path)

          # Create symbolic link
          File.symlink(entry.data, output_path)
        end

        # Set file attributes (permissions and timestamps)
        #
        # @param entry [Entry] Entry with attributes
        # @param path [String] File path
        def set_entry_attributes(entry, path)
          # Set modification time
          if entry.mtime&.positive?
            mtime = Time.at(entry.mtime)
            File.utime(mtime, mtime, path)
          end

          # Set permissions
          File.chmod(entry.mode & 0o7777, path) if entry.mode
        rescue Errno::EPERM, Errno::ENOENT
          # Permission errors are non-fatal
        end
      end
    end
  end
end
