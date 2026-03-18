# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Omnizip
  module Formats
    module Msi
      # MSI Package Reader
      #
      # Handles parsing and extraction of MSI packages.
      # Uses OLE storage internally for reading embedded cabinets
      # and resolving directory paths.
      class Reader
        include Omnizip::Formats::Msi::Constants

        # @return [String] Path to MSI file
        attr_reader :path

        # @return [Ole::Storage] OLE storage object
        attr_reader :ole

        # @return [StringPool] String pool for interned strings
        attr_reader :string_pool

        # @return [TableParser] Table parser
        attr_reader :table_parser

        # @return [CabExtractor] Cab extractor
        attr_reader :cab_extractor

        # @return [DirectoryResolver] Directory resolver
        attr_reader :directory_resolver

        # @return [Hash<String, String>] Component to directory mapping
        attr_reader :component_dirs

        # @return [Array<Entry>] File entries (from File table)
        attr_reader :entries

        # Initialize MSI package reader
        #
        # @param path [String] Path to MSI file
        def initialize(path)
          @path = path
          @entries = nil
          @component_dirs = {}
        end

        # Open MSI file and parse tables
        #
        # @return [Reader] self
        def open
          @ole = Ole::Storage.open(@path)
          build_stream_name_map
          @string_pool = StringPool.new(@ole, method(:read_stream))
          @table_parser = TableParser.new(@string_pool, method(:read_stream))
          @directory_resolver = DirectoryResolver.new(@table_parser.table(DIRECTORY_TABLE))
          build_component_dirs
          @cab_extractor = CabExtractor.new(@ole, @table_parser.table(MEDIA_TABLE), @path, method(:read_stream))
          self
        end

        # Close MSI file
        def close
          @ole&.close
          @ole = nil
        end

        # Get file entries from File table
        #
        # @return [Array<Entry>] File entries
        def files
          @entries ||= build_entries
        end

        # Alias for files
        #
        # @return [Array<Entry>] File entries
        alias entries files

        # Extract all files to output directory
        #
        # @param output_dir [String] Output directory path
        # @return [Array<String>] Extracted file paths
        def extract(output_dir)
          FileUtils.mkdir_p(output_dir)

          # Extract files from cabinets
          cabinets = @cab_extractor.extract_cabinets
          extracted_files = extract_from_cabinets(cabinets, output_dir)

          # Clean up temp cabinet files
          cleanup_cabinets(cabinets)

          extracted_files
        end

        # Get information about MSI package
        #
        # @return [Hash] Package information
        def info
          {
            path: @path,
            file_count: files.size,
            tables: @table_parser.table_names,
          }
        end

        private

        # Build stream name map for encoded stream names
        def build_stream_name_map
          @stream_name_map = {}

          return unless @ole&.root

          @ole.root.children.each do |child|
            # Decode the stream name
            encoded_name = child.name
            decoded_name = decode_stream_name(encoded_name)
            @stream_name_map[decoded_name] = encoded_name
          end
        end

        # Decode MSI stream name from OLE storage
        #
        # @param encoded_name [String] Encoded stream name
        # @return [String] Decoded stream name
        def decode_stream_name(encoded_name)
          Constants.decode_stream_name(encoded_name)
        end

        # Read stream from OLE storage
        #
        # @param base_name [String] Base stream name (e.g., "_StringPool")
        # @return [String, nil] Stream content or nil
        def read_stream(base_name)
          # Try encoded name from the map first
          if @stream_name_map && @stream_name_map.key?(base_name)
            encoded = @stream_name_map[base_name]
            data = try_read_stream(encoded)
            return data if data && !data.empty?
          end

          # Try various encodings of the stream name
          candidates = build_stream_name_candidates(base_name)

          candidates.each do |name|
            data = try_read_stream(name)
            return data if data && !data.empty?
          end

          nil
        end

        # Build possible stream name variations
        #
        # @param base_name [String] Base stream name
        # @return [Array<String>] Possible stream names
        def build_stream_name_candidates(base_name)
          candidates = []

          # Try with standard prefix bytes
          # MSI uses \x01 or \x05 prefix followed by UTF-16LE encoded name
          utf16le = base_name.encode("UTF-16LE")
          [1, 5].each do |prefix|
            candidates << "#{prefix.chr.b}".b << utf16le.b
          end

          # Try plain ASCII name
          candidates << base_name

          candidates.uniq
        end

        # Attempt to read a stream
        #
        # @param name [String] Stream name
        # @return [String, nil] Stream content or nil
        def try_read_stream(name)
          @ole.read(name)
        rescue StandardError
          nil
        end

        # Build component to directory mapping from Component table
        def build_component_dirs
          component_table = @table_parser.table(COMPONENT_TABLE)
          return unless component_table

          component_table.each do |row|
            component_key = row["Component"]
            dir_key = row["Directory_"]
            @component_dirs[component_key] = dir_key if component_key && dir_key
          end
        end

        # Build file entries from File table
        #
        # @return [Array<Entry>] File entries
        def build_entries
          entries = []

          file_table = @table_parser.table(FILE_TABLE)
          return entries if file_table.nil? || file_table.empty?

          file_table.each do |row|
            entry = Entry.new
            entry.file_key = row["File"]
            entry.component = row["Component_"]
            entry.parse_filename(row["FileName"])
            entry.size = row["FileSize"] || 0
            entry.sequence = row["Sequence"] || 0
            entry.version = row["Version"]
            entry.language = row["Language"]
            entry.attributes = row["Attributes"]

            # Resolve directory path
            dir_key = @component_dirs[entry.component]
            dir_path = @directory_resolver&.resolve_path(dir_key) || ""

            entry.path = File.join(dir_path, entry.display_name)

            entries << entry
          end

          entries
        end

        # Extract files from cabinets to output directory
        #
        # @param cabinets [Hash] Cabinet info from CabExtractor
        # @param output_dir [String] Output directory
        # @return [Array<String>] Extracted file paths
        def extract_from_cabinets(cabinets, output_dir)
          extracted_files = []

          # Get all file entries sorted by sequence
          file_entries = files.sort_by(&:sequence)

          file_entries.each do |entry|
            # Find the cabinet containing this file
            cab_info = @cab_extractor.find_cabinet_for_sequence(entry.sequence, cabinets)
            next unless cab_info

            # Extract file from cabinet
            extracted_path = extract_file_from_cab(entry, cab_info[:path], output_dir)
            extracted_files << extracted_path if extracted_path
          end

          extracted_files
        end

        # Extract a single file from cabinet
        #
        # @param entry [Entry] File entry
        # @param cab_path [String] Path to cabinet file
        # @param output_dir [String] Output directory
        # @return [String, nil] Extracted file path or nil
        def extract_file_from_cab(entry, cab_path, output_dir)
          return nil unless cab_path && File.exist?(cab_path)

          require "cabriolet"

          decompressor = Cabriolet::CAB::Decompressor.new
          cabinet = decompressor.open(cab_path)

          target_path = File.join(output_dir, entry.path)
          target_dir = File.dirname(target_path)

          FileUtils.mkdir_p(target_dir)

          # Find the file in the cabinet by file_key (MSI stores files by key, not name)
          cab_file = cabinet.files.find do |f|
            f.filename == entry.file_key
          end

          if cab_file
            decompressor.extract_file(cab_file, target_path)
            return target_path
          end

          nil
        rescue StandardError
          nil
        end

        # Clean up temporary cabinet files
        #
        # @param cabinets [Hash] Cabinet info from CabExtractor
        def cleanup_cabinets(cabinets)
          cabinets.each_value do |cab_info|
            cab_info[:temp_file]&.close!
          rescue StandardError
            # Ignore errors during cleanup
          end
        end
      end
    end
  end
end
