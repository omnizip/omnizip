# frozen_string_literal: true

module Omnizip
  module Metadata
    # Validates metadata changes before applying
    class MetadataValidator
      # Validate entry metadata
      # @param metadata [EntryMetadata] Metadata to validate
      # @raise [ArgumentError] If metadata is invalid
      def validate_entry(metadata)
        validate_comment(metadata.comment) if metadata.comment
        validate_time(metadata.mtime) if metadata.respond_to?(:mtime)
        validate_permissions(metadata.unix_permissions) if metadata.unix_permissions

        true
      end

      # Validate archive metadata
      # @param metadata [ArchiveMetadata] Metadata to validate
      # @raise [ArgumentError] If metadata is invalid
      def validate_archive(metadata)
        validate_comment(metadata.comment) if metadata.comment

        true
      end

      # Validate comment length
      # @param comment [String] Comment to validate
      # @raise [ArgumentError] If comment is too long
      def validate_comment(comment)
        max_length = 65_535 # ZIP format limit
        return true if comment.bytesize <= max_length

        raise ArgumentError,
              "Comment too long: #{comment.bytesize} bytes (max: #{max_length})"
      end

      # Validate time value
      # @param time [Time] Time to validate
      # @raise [ArgumentError] If time is invalid
      def validate_time(time)
        return true unless time

        unless time.is_a?(Time)
          raise ArgumentError, "Time must be a Time object, got #{time.class}"
        end

        # DOS time range: 1980-01-01 to 2107-12-31
        min_time = Time.new(1980, 1, 1)
        max_time = Time.new(2107, 12, 31, 23, 59, 59)

        if time < min_time || time > max_time
          raise ArgumentError, "Time out of DOS range (1980-2107): #{time}"
        end

        true
      end

      # Validate Unix permissions
      # @param perms [Integer] Permissions to validate
      # @raise [ArgumentError] If permissions are invalid
      def validate_permissions(perms)
        return true unless perms

        unless perms.is_a?(Integer)
          raise ArgumentError,
                "Permissions must be an integer, got #{perms.class}"
        end

        unless (0..0o777).cover?(perms)
          raise ArgumentError,
                "Permissions out of range: 0#{perms.to_s(8)} (max: 0777)"
        end

        true
      end

      # Validate filename
      # @param filename [String] Filename to validate
      # @raise [ArgumentError] If filename is invalid
      def validate_filename(filename)
        return true unless filename

        max_length = 65_535 # ZIP format limit
        if filename.bytesize > max_length
          raise ArgumentError,
                "Filename too long: #{filename.bytesize} bytes (max: #{max_length})"
        end

        # Check for invalid characters
        if filename.include?("\x00")
          raise ArgumentError, "Filename contains null character"
        end

        true
      end
    end
  end
end
