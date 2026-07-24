# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Models
        # Represents a RAR volume in a multi-volume set
        class RarVolume
          attr_accessor :path, :volume_number, :is_first, :is_last,
                        :size, :archive_flags

          # Initialize RAR volume
          #
          # @param path [String] Path to volume file
          # @param volume_number [Integer] Volume number (0-based)
          def initialize(path, volume_number = 0)
            @path = path
            @volume_number = volume_number
            @is_first = false
            @is_last = false
            @size = nil
            @archive_flags = 0
          end

          # Check if this is the first volume
          #
          # @return [Boolean] true if first volume
          def first?
            @is_first
          end

          # Check if this is the last volume
          #
          # @return [Boolean] true if last volume
          def last?
            @is_last
          end

          # Get volume file size
          #
          # @return [Integer] File size in bytes
          def file_size
            @file_size ||= File.size(@path)
          end

          # Check if file exists
          #
          # @return [Boolean] true if volume file exists
          def exist?
            File.exist?(@path)
          end
        end
      end
    end
  end
end
