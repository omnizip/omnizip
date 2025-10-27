# frozen_string_literal: true

module Omnizip
  module Formats
    module SevenZip
      module Models
        # Represents a file entry in .7z archive
        # Contains file metadata, attributes, and extraction information
        class FileEntry
          attr_accessor :name, :size, :compressed_size, :crc, :is_dir,
                        :is_empty, :is_anti, :has_stream, :mtime, :atime,
                        :ctime, :attributes, :folder_index, :file_index,
                        :source_path

          # Initialize file entry
          def initialize
            @name = nil
            @size = 0
            @compressed_size = 0
            @crc = nil
            @is_dir = false
            @is_empty = false
            @is_anti = false
            @has_stream = true
            @mtime = nil
            @atime = nil
            @ctime = nil
            @attributes = nil
            @folder_index = nil
            @file_index = nil
            @source_path = nil
          end

          # Check if entry is a directory
          #
          # @return [Boolean] true if directory
          def directory?
            @is_dir
          end

          # Check if entry is a file
          #
          # @return [Boolean] true if regular file
          def file?
            !@is_dir
          end

          # Check if entry has data stream
          #
          # @return [Boolean] true if has stream
          def has_stream?
            @has_stream && !@is_empty
          end
        end
      end
    end
  end
end
