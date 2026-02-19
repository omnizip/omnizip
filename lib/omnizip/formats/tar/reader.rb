# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "entry"

module Omnizip
  module Formats
    module Tar
      # TAR archive reader
      #
      # Reads and extracts TAR archives
      class Reader
        include Constants

        attr_reader :file_path, :entries

        # Initialize TAR reader
        #
        # @param file_path [String] Path to TAR archive
        def initialize(file_path)
          @file_path = file_path
          @entries = []
          @file = nil
        end

        # Read TAR archive and parse all entries
        #
        # @return [self] Returns self for method chaining
        def read
          File.open(@file_path, "rb") do |file|
            @file = file
            parse_entries
          end
          self
        end

        # Extract all entries to a directory
        #
        # @param output_dir [String] Output directory path
        def extract_all(output_dir)
          read unless @entries.any?

          FileUtils.mkdir_p(output_dir)

          @entries.each do |entry|
            extract_entry(entry, output_dir)
          end
        end

        # Extract a specific entry
        #
        # @param entry [Entry] Entry to extract
        # @param output_dir [String] Output directory
        def extract_entry(entry, output_dir)
          full_path = File.join(output_dir, entry.full_name)

          if entry.directory?
            FileUtils.mkdir_p(full_path)
          elsif entry.file?
            FileUtils.mkdir_p(File.dirname(full_path))
            File.binwrite(full_path, entry.data)
            File.chmod(entry.mode, full_path) if entry.mode
            File.utime(entry.mtime, entry.mtime, full_path) if entry.mtime
          elsif entry.symlink?
            FileUtils.mkdir_p(File.dirname(full_path))
            File.symlink(entry.linkname, full_path)
          end
        end

        # List all entries
        #
        # @return [Array<Entry>] List of entries
        def list_entries
          read unless @entries.any?
          @entries
        end

        # Open TAR archive and yield reader
        #
        # @param file_path [String] Path to TAR archive
        # @yield [Reader] Reader instance
        def self.open(file_path)
          reader = new(file_path)
          reader.read
          yield reader if block_given?
          reader
        end

        private

        # Parse all entries from TAR archive
        def parse_entries
          @entries = []

          loop do
            header_data = @file.read(HEADER_SIZE)
            break if header_data.nil? || header_data.bytesize < HEADER_SIZE

            entry = Header.parse(header_data)
            break if entry.nil?

            # Read entry data
            if entry.size.positive?
              entry.data = @file.read(entry.size)

              # Skip to next block boundary
              remainder = entry.size % BLOCK_SIZE
              if remainder.positive?
                padding = BLOCK_SIZE - remainder
                @file.read(padding)
              end
            end

            @entries << entry
          end
        end
      end
    end
  end
end
