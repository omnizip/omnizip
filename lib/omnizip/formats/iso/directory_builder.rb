# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # ISO 9660 Directory Structure Builder
      #
      # Builds the hierarchical directory structure for an ISO image,
      # allocating sectors for directories and files.
      class DirectoryBuilder
        # @return [Array<Hash>] Files to add
        attr_reader :files

        # @return [Array<Hash>] Directories to add
        attr_reader :directories

        # @return [Integer] ISO level
        attr_reader :level

        # @return [Boolean] Rock Ridge enabled
        attr_reader :rock_ridge

        # Initialize directory builder
        #
        # @param files [Array<Hash>] Files to include
        # @param directories [Array<Hash>] Directories to include
        # @param options [Hash] Builder options
        def initialize(files, directories, options = {})
          @files = files
          @directories = directories
          @level = options.fetch(:level, 2)
          @rock_ridge = options.fetch(:rock_ridge, false)
          @current_sector = 22 # After volume descriptors and path tables
        end

        # Build directory structure
        #
        # @return [Hash] Complete directory structure with allocations
        def build
          # Build directory tree
          tree = build_directory_tree

          # Allocate sectors for directories and files
          allocate_sectors(tree)

          # Build path table
          path_table = build_path_table(tree)

          {
            root: tree,
            directories: flatten_directories(tree),
            files: @files,
            path_table: path_table,
            path_table_size: path_table.bytesize,
            total_sectors: @current_sector
          }
        end

        private

        # Build directory tree from files and directories
        #
        # @return [Hash] Root directory node
        def build_directory_tree
          root = {
            name: "\x00", # Root directory identifier
            iso_path: "",
            children: [],
            directory: true,
            stat: nil
          }

          # Add all directories first
          @directories.each do |dir_info|
            add_to_tree(root, dir_info[:iso_path], dir_info)
          end

          # Add all files
          @files.each do |file_info|
            add_to_tree(root, file_info[:iso_path], file_info)
          end

          root
        end

        # Add entry to directory tree
        #
        # @param root [Hash] Root node
        # @param path [String] Entry path
        # @param info [Hash] Entry information
        def add_to_tree(root, path, info)
          parts = path.split("/")
          current = root

          # Navigate/create directory structure
          parts[0...-1].each do |part|
            child = current[:children].find { |c| c[:name] == part }

            unless child
              child = {
                name: part,
                iso_path: [current[:iso_path], part].reject(&:empty?).join("/"),
                children: [],
                directory: true,
                stat: nil
              }
              current[:children] << child
            end

            current = child
          end

          # Add the actual entry
          entry_name = parts.last
          entry = {
            name: entry_name,
            iso_path: path,
            children: info[:directory] ? [] : nil,
            directory: info[:directory] || false,
            stat: info[:stat],
            source: info[:source],
            size: info[:directory] ? 0 : File.size(info[:source])
          }

          current[:children] << entry
        end

        # Allocate sectors for all entries
        #
        # @param tree [Hash] Directory tree
        def allocate_sectors(tree)
          # Allocate for root directory
          allocate_directory_sectors(tree)

          # Recursively allocate for children
          allocate_children_sectors(tree)

          # Allocate for files
          allocate_file_sectors
        end

        # Allocate sectors for a directory
        #
        # @param dir_node [Hash] Directory node
        def allocate_directory_sectors(dir_node)
          # Calculate directory size
          dir_size = calculate_directory_size(dir_node)
          sectors_needed = (dir_size.to_f / Iso::SECTOR_SIZE).ceil

          # Allocate location
          dir_node[:location] = @current_sector
          dir_node[:size] = dir_size

          @current_sector += sectors_needed
        end

        # Calculate directory data size
        #
        # @param dir_node [Hash] Directory node
        # @return [Integer] Size in bytes
        def calculate_directory_size(dir_node)
          size = 0

          # Size for "." entry (34 bytes minimum)
          size += 34

          # Size for ".." entry
          size += 34

          # Size for each child entry
          dir_node[:children].each do |child|
            name_len = child[:name].bytesize
            padding = name_len.even? ? 1 : 0
            entry_size = 33 + name_len + padding

            # Add Rock Ridge System Use fields if enabled
            entry_size += calculate_rock_ridge_size(child) if @rock_ridge

            size += entry_size
          end

          # Round up to sector boundary
          ((size.to_f / Iso::SECTOR_SIZE).ceil * Iso::SECTOR_SIZE)
        end

        # Calculate Rock Ridge System Use field size
        #
        # @param entry [Hash] Entry information
        # @return [Integer] Size in bytes
        def calculate_rock_ridge_size(entry)
          # Basic Rock Ridge fields:
          # - PX (POSIX attributes): 44 bytes
          # - TF (timestamps): 26 bytes
          # - NM (alternate name): variable
          # For now, estimate 100 bytes
          100
        end

        # Allocate sectors for children recursively
        #
        # @param dir_node [Hash] Directory node
        def allocate_children_sectors(dir_node)
          dir_node[:children].each do |child|
            next unless child[:directory]

            allocate_directory_sectors(child)
            allocate_children_sectors(child)
          end
        end

        # Allocate sectors for files
        def allocate_file_sectors
          @files.each do |file_info|
            file_size = file_info[:stat].size
            sectors_needed = (file_size.to_f / Iso::SECTOR_SIZE).ceil

            file_info[:location] = @current_sector
            file_info[:size] = file_size

            @current_sector += sectors_needed
          end
        end

        # Build path table from directory tree
        #
        # @param tree [Hash] Directory tree
        # @return [String] Path table data
        def build_path_table(tree)
          table = String.new
          directories = []

          # Collect all directories in path table order
          collect_directories_for_path_table(tree, directories)

          # Build path table entries
          directories.each_with_index do |dir, idx|
            name = dir[:name] == "\x00" ? "\x00" : dir[:name]
            parent_idx = dir[:parent_idx] || 0

            # Name length
            table << [name.bytesize].pack("C")

            # Extended attribute length
            table << [0].pack("C")

            # Location of extent
            table << [dir[:location]].pack("V")

            # Parent directory number (1-based)
            table << [parent_idx + 1].pack("v")

            # Directory name
            table << name

            # Pad to even length
            table << "\x00" if name.bytesize.odd?
          end

          table
        end

        # Collect directories in depth-first order for path table
        #
        # @param node [Hash] Current node
        # @param list [Array<Hash>] Output list
        # @param parent_idx [Integer, nil] Parent index
        def collect_directories_for_path_table(node, list, parent_idx = nil)
          current_idx = list.size
          node[:parent_idx] = parent_idx
          list << node

          node[:children].select { |c| c[:directory] }.each do |child|
            collect_directories_for_path_table(child, list, current_idx)
          end
        end

        # Flatten directory tree to array
        #
        # @param tree [Hash] Directory tree
        # @return [Array<Hash>] Flat directory list
        def flatten_directories(tree)
          result = [tree]

          tree[:children].select { |c| c[:directory] }.each do |child|
            result.concat(flatten_directories(child))
          end

          result
        end
      end
    end
  end
end