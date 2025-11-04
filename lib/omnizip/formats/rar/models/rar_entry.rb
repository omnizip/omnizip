# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Models
        # Represents a file entry in RAR archive
        # Contains file metadata and extraction information
        class RarEntry
          attr_accessor :name, :size, :compressed_size, :crc, :is_dir,
                        :host_os, :mtime, :attributes, :method,
                        :version, :flags, :volume_index, :split_before,
                        :split_after, :encrypted

          # Initialize RAR entry
          def initialize
            @name = nil
            @size = 0
            @compressed_size = 0
            @crc = nil
            @is_dir = false
            @host_os = 0
            @mtime = nil
            @attributes = nil
            @method = 0
            @version = 0
            @flags = 0
            @volume_index = 0
            @split_before = false
            @split_after = false
            @encrypted = false
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

          # Check if entry is encrypted
          #
          # @return [Boolean] true if encrypted
          def encrypted?
            @encrypted
          end

          # Check if entry spans volumes
          #
          # @return [Boolean] true if split across volumes
          def split?
            @split_before || @split_after
          end
        end
      end
    end
  end
end
