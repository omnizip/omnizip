# frozen_string_literal: true

require "fileutils"
require_relative "models/file_entry"

module Omnizip
  module Formats
    module SevenZip
      # Collects files and directories for archiving
      # Handles file metadata, timestamps, and attributes
      class FileCollector
        attr_reader :entries

        # Initialize collector
        def initialize
          @entries = []
          @base_path = nil
        end

        # Add path (file or directory) to collection
        #
        # @param path [String] Path to file or directory
        # @param archive_path [String, nil] Path in archive (nil = auto)
        # @param recursive [Boolean] Recursively add directories
        def add_path(path, archive_path: nil, recursive: true)
          path = File.expand_path(path)
          raise "Path not found: #{path}" unless File.exist?(path)

          @base_path ||= File.dirname(path)

          if File.directory?(path)
            add_directory(path, archive_path, recursive)
          else
            add_file(path, archive_path)
          end
        end

        # Add files matching glob pattern
        #
        # @param pattern [String] Glob pattern
        # @param base_path [String, nil] Base path for relative names
        def add_glob(pattern, base_path: nil)
          @base_path ||= base_path || Dir.pwd

          Dir.glob(pattern).each do |path|
            add_path(path)
          end
        end

        # Get collected file entries
        #
        # @return [Array<Models::FileEntry>] File entries
        def collect_files
          @entries.sort_by(&:name)
        end

        private

        # Add single file
        #
        # @param file_path [String] Full path to file
        # @param archive_path [String, nil] Path in archive
        def add_file(file_path, archive_path)
          archive_name = archive_path || relative_path(file_path)

          entry = Models::FileEntry.new.tap do |e|
            e.name = archive_name
            e.size = File.size(file_path)
            e.has_stream = e.size.positive?
            e.is_dir = false
            e.mtime = File.mtime(file_path)
            e.attributes = file_attributes(file_path)
            e.source_path = file_path
          end

          @entries << entry
        end

        # Add directory and optionally its contents
        #
        # @param dir_path [String] Directory path
        # @param archive_path [String, nil] Path in archive
        # @param recursive [Boolean] Add contents recursively
        def add_directory(dir_path, archive_path, recursive)
          archive_name = archive_path || relative_path(dir_path)
          archive_name += "/" unless archive_name.end_with?("/")

          # Add directory entry
          entry = Models::FileEntry.new.tap do |e|
            e.name = archive_name
            e.size = 0
            e.has_stream = false
            e.is_dir = true
            e.mtime = File.mtime(dir_path)
            e.attributes = file_attributes(dir_path)
          end

          @entries << entry

          return unless recursive

          # Add contents
          Dir.each_child(dir_path) do |child|
            child_path = File.join(dir_path, child)
            add_path(child_path, archive_path: nil, recursive: true)
          end
        end

        # Get relative path for archive
        #
        # @param path [String] Full path
        # @return [String] Relative path
        def relative_path(path)
          if @base_path && path.start_with?(@base_path)
            path[@base_path.length..].sub(%r{^/}, "")
          else
            File.basename(path)
          end
        end

        # Get file attributes (Unix permissions as Windows attributes)
        #
        # @param path [String] File path
        # @return [Integer] Attribute flags
        def file_attributes(path)
          attrs = 0
          stat = File.stat(path)

          # Windows FILE_ATTRIBUTE_DIRECTORY = 0x10
          attrs |= 0x10 if stat.directory?

          # Windows FILE_ATTRIBUTE_ARCHIVE = 0x20
          attrs |= 0x20 unless stat.directory?

          # Convert Unix permissions to Windows read-only flag
          # FILE_ATTRIBUTE_READONLY = 0x01
          attrs |= 0x01 unless stat.writable?

          attrs
        end
      end
    end
  end
end
