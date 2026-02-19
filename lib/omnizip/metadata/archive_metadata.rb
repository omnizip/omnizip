# frozen_string_literal: true

module Omnizip
  module Metadata
    # Model for archive-level metadata
    class ArchiveMetadata
      attr_reader :archive

      # Initialize archive metadata
      # @param archive [Omnizip::Zip::File] The archive to manage metadata for
      def initialize(archive)
        @archive = archive
        @modified = false
      end

      # Get archive comment
      # @return [String] Archive comment
      def comment
        archive.comment
      end

      # Set archive comment
      # @param value [String] New comment
      def comment=(value)
        archive.comment = value.to_s
        @modified = true
      end

      # Get creation date (approximated from first entry)
      # @return [Time, nil] Creation date or nil
      def created_at
        return nil if archive.entries.empty?

        archive.entries.map(&:time).min
      end

      # Get modification date (from newest entry)
      # @return [Time, nil] Modification date or nil
      def modified_at
        return nil if archive.entries.empty?

        archive.entries.map(&:time).max
      end

      # Get total uncompressed size
      # @return [Integer] Total uncompressed size in bytes
      def total_size
        archive.entries.sum(&:size)
      end

      # Get total compressed size
      # @return [Integer] Total compressed size in bytes
      def total_compressed_size
        archive.entries.sum(&:compressed_size)
      end

      # Get compression ratio
      # @return [Float] Compression ratio (0.0 to 1.0)
      def compression_ratio
        return 0.0 if total_size.zero?

        ratio = 1.0 - (total_compressed_size.to_f / total_size)
        # Clamp ratio between 0.0 and 1.0 (compressed size can exceed
        # original size for small files or incompressible data)
        [[ratio, 0.0].max, 1.0].min
      end

      # Get entry count
      # @return [Integer] Number of entries
      def entry_count
        archive.entries.size
      end

      # Get file count (excluding directories)
      # @return [Integer] Number of files
      def file_count
        archive.entries.count(&:file?)
      end

      # Get directory count
      # @return [Integer] Number of directories
      def directory_count
        archive.entries.count(&:directory?)
      end

      # Check if metadata has been modified
      # @return [Boolean] True if modified
      def modified?
        @modified
      end

      # Reset modified flag
      def reset_modified
        @modified = false
      end

      # Get all metadata as a hash
      # @return [Hash] Metadata hash
      def to_h
        {
          comment: comment,
          created_at: created_at,
          modified_at: modified_at,
          total_size: total_size,
          total_compressed_size: total_compressed_size,
          compression_ratio: compression_ratio,
          entry_count: entry_count,
          file_count: file_count,
          directory_count: directory_count,
        }
      end
    end
  end
end
