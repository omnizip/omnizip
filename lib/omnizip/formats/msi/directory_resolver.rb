# frozen_string_literal: true

require "set"

module Omnizip
  module Formats
    module Msi
      # MSI Directory Resolver
      #
      # Resolves the full installation path for files by traversing
      # the Directory table hierarchy. MSI uses a self-referential
      # structure where each directory entry references its parent.
      #
      # Directory table columns:
      # - Directory: Primary key (directory identifier)
      # - Directory_Parent: Parent directory reference (nil for root)
      # - DefaultDir: Directory name format "Source|Target" or "Name"
      class DirectoryResolver
        include Omnizip::Formats::Msi::Constants

        # @return [Hash] Directory table data
        attr_reader :directory_table

        # @return [Hash] Directory cache (key => full path)
        attr_reader :path_cache

        # @return [Hash] Directory info (key => {parent, name, default_dir})
        attr_reader :directories

        # Initialize resolver with directory table
        #
        # @param directory_table [Array<Hash>] Parsed Directory table rows
        def initialize(directory_table)
          @directory_table = directory_table || []
          @path_cache = {}
          @directories = {}
          build_directory_map
        end

        # Resolve full path for a directory key
        #
        # @param directory_key [String] Directory identifier
        # @return [String] Full path (empty string if not found)
        def resolve_path(directory_key)
          return "" if directory_key.nil? || directory_key.empty?

          # Check cache
          return @path_cache[directory_key] if @path_cache.key?(directory_key)

          # Resolve path
          path = build_path(directory_key, Set.new)
          @path_cache[directory_key] = path
          path
        end

        # Get the source directory name for a directory key
        #
        # @param directory_key [String] Directory identifier
        # @return [String, nil] Source directory name
        def source_name(directory_key)
          dir_info = @directories[directory_key]
          return nil unless dir_info

          parse_default_dir(dir_info[:default_dir])[:source]
        end

        # Get the target directory name for a directory key
        #
        # @param directory_key [String] Directory identifier
        # @return [String, nil] Target directory name
        def target_name(directory_key)
          dir_info = @directories[directory_key]
          return nil unless dir_info

          parse_default_dir(dir_info[:default_dir])[:target]
        end

        private

        # Build directory map from table
        def build_directory_map
          @directory_table.each do |row|
            key = row["Directory"]
            next unless key

            @directories[key] = {
              key: key,
              parent: row["Directory_Parent"],
              default_dir: row["DefaultDir"],
              name: parse_default_dir(row["DefaultDir"])[:target],
            }
          end
        end

        # Build full path for directory, recursively walking parent chain
        #
        # @param key [String] Current directory key
        # @param visited [Set] Set of visited keys (cycle detection)
        # @return [String] Full path
        def build_path(key, visited)
          return "" if key.nil? || key.empty?

          # Check for circular reference
          return "" if visited.include?(key)

          dir_info = @directories[key]
          return "" unless dir_info

          visited.add(key)

          # Get directory name
          name_info = parse_default_dir(dir_info[:default_dir])
          name = name_info[:target] || name_info[:source] || ""

          # Handle root directories
          parent_key = dir_info[:parent]
          if parent_key.nil? || parent_key.empty? || parent_key == key
            # This is a root directory
            return normalize_root_name(name)
          end

          # Build parent path recursively
          parent_path = build_path(parent_key, visited)

          # Combine paths
          if parent_path.empty?
            normalize_root_name(name)
          else
            File.join(parent_path, name)
          end
        end

        # Parse DefaultDir format
        #
        # Format: "Source|Target" or "Name"
        # The source name is used during installation from source media.
        # The target name is used for the installed directory name.
        #
        # @param default_dir [String] DefaultDir value
        # @return [Hash] {source:, target:}
        def parse_default_dir(default_dir)
          if default_dir.nil? || default_dir.empty?
            return { source: "",
                     target: "" }
          end

          # Check for source|target format
          if default_dir.include?("|")
            parts = default_dir.split("|", 2)
            {
              source: parts[0] || "",
              target: parts[1] || parts[0] || "",
            }
          else
            # Single name - use for both source and target
            {
              source: default_dir,
              target: default_dir,
            }
          end
        end

        # Normalize root directory name
        #
        # Maps special MSI directory properties to standard names.
        #
        # @param name [String] Directory name
        # @return [String] Normalized name
        def normalize_root_name(name)
          case name
          when TARGET_DIR, SOURCE_DIR
            "SourceDir"
          when PROGRAM_FILES
            "Program Files"
          when PROGRAM_FILES_X64
            "Program Files (x86)"
          when WINDOWS_FOLDER
            "Windows"
          when SYSTEM_FOLDER, SYSTEM_X64_FOLDER
            "System"
          else
            name
          end
        end
      end
    end
  end
end
