# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Models
        # Represents a RAR archive with metadata
        class RarArchive
          attr_accessor :path, :version, :flags, :volumes, :entries,
                        :total_size, :compressed_size, :is_multi_volume,
                        :comment, :has_recovery, :recovery_percent,
                        :recovery_files

          # Initialize RAR archive
          #
          # @param path [String] Path to RAR archive
          def initialize(path)
            @path = path
            @version = nil
            @flags = 0
            @volumes = []
            @entries = []
            @total_size = 0
            @compressed_size = 0
            @is_multi_volume = false
            @comment = nil
            @has_recovery = false
            @recovery_percent = 0
            @recovery_files = []
          end

          # Check if archive has recovery records
          #
          # @return [Boolean] true if recovery available
          def has_recovery_records?
            @has_recovery || @recovery_files.any?
          end

          # Get recovery file paths
          #
          # @return [Array<String>] Paths to .rev files
          def recovery_file_paths
            @recovery_files
          end

          # Check if archive is multi-volume
          #
          # @return [Boolean] true if multi-volume archive
          def multi_volume?
            @is_multi_volume
          end

          # Get total number of volumes
          #
          # @return [Integer] Number of volumes
          def total_volumes
            @volumes.size
          end

          # Get RAR format version string
          #
          # @return [String] Version string (RAR4 or RAR5)
          def format_version
            @version == 5 ? "RAR5" : "RAR4"
          end

          # Get total number of entries
          #
          # @return [Integer] Number of entries
          def entry_count
            @entries.size
          end
        end
      end
    end
  end
end
