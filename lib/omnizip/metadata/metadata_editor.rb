# frozen_string_literal: true

require_relative "metadata_validator"

module Omnizip
  module Metadata
    # Coordinates metadata editing operations
    class MetadataEditor
      attr_reader :archive, :validator

      # Initialize metadata editor
      # @param archive [Omnizip::Zip::File] Archive to edit
      def initialize(archive)
        @archive = archive
        @validator = MetadataValidator.new
        @changes = []
      end

      # Set timestamps for all entries
      # @param time [Time] Time to set
      # @param filter [Proc] Optional filter to select entries
      def set_all_timestamps(time, &filter)
        validator.validate_time(time)

        entries = filter ? archive.entries.select(&filter) : archive.entries

        entries.each do |entry|
          next if entry.directory?

          metadata = EntryMetadata.new(entry)
          metadata.mtime = time
          @changes << { entry: entry, field: :mtime, value: time }
        end

        self
      end

      # Normalize permissions (set sensible defaults)
      # @param file_perms [Integer] Permissions for files (default: 0644)
      # @param dir_perms [Integer] Permissions for directories (default: 0755)
      def normalize_permissions(file_perms: 0o644, dir_perms: 0o755)
        validator.validate_permissions(file_perms)
        validator.validate_permissions(dir_perms)

        archive.entries.each do |entry|
          metadata = EntryMetadata.new(entry)
          perms = entry.directory? ? dir_perms : file_perms
          metadata.unix_permissions = perms
          @changes << { entry: entry, field: :permissions, value: perms }
        end

        self
      end

      # Strip all comments from entries and archive
      def strip_comments
        archive.entries.each do |entry|
          metadata = EntryMetadata.new(entry)
          metadata.comment = ""
          @changes << { entry: entry, field: :comment, value: "" }
        end

        archive.comment = ""
        @changes << { entry: :archive, field: :comment, value: "" }

        self
      end

      # Set comment for entries matching a pattern
      # @param pattern [String, Regexp] Pattern to match
      # @param comment [String] Comment to set
      def set_comment_matching(pattern, comment)
        validator.validate_comment(comment)

        matching_entries = if pattern.is_a?(Regexp)
                             archive.entries.select { |e| e.name =~ pattern }
                           else
                             archive.entries.select do |e|
                               ::File.fnmatch(pattern, e.name)
                             end
                           end

        matching_entries.each do |entry|
          metadata = EntryMetadata.new(entry)
          metadata.comment = comment
          @changes << { entry: entry, field: :comment, value: comment }
        end

        self
      end

      # Set permissions for entries matching a pattern
      # @param pattern [String, Regexp] Pattern to match
      # @param perms [Integer] Permissions to set
      def set_permissions_matching(pattern, perms)
        validator.validate_permissions(perms)

        matching_entries = if pattern.is_a?(Regexp)
                             archive.entries.select { |e| e.name =~ pattern }
                           else
                             archive.entries.select do |e|
                               ::File.fnmatch(pattern, e.name)
                             end
                           end

        matching_entries.each do |entry|
          next if entry.directory?

          metadata = EntryMetadata.new(entry)
          metadata.unix_permissions = perms
          @changes << { entry: entry, field: :permissions, value: perms }
        end

        self
      end

      # Update timestamps to preserve relative ordering
      # Useful for maintaining build timestamps while updating absolute times
      # @param base_time [Time] Base time for earliest file
      def preserve_relative_timestamps(base_time = Time.now)
        validator.validate_time(base_time)

        # Find earliest timestamp
        earliest = archive.entries.map(&:time).min
        return self unless earliest

        # Calculate offset
        offset = base_time.to_i - earliest.to_i

        archive.entries.each do |entry|
          next if entry.directory?

          new_time = Time.at(entry.time.to_i + offset)
          metadata = EntryMetadata.new(entry)
          metadata.mtime = new_time
          @changes << { entry: entry, field: :mtime, value: new_time }
        end

        self
      end

      # Get list of pending changes
      # @return [Array<Hash>] List of changes
      def pending_changes
        @changes
      end

      # Check if there are pending changes
      # @return [Boolean] True if there are changes
      def modified?
        !@changes.empty?
      end

      # Clear pending changes
      def clear_changes
        @changes = []
        self
      end

      # Commit all changes to archive
      # This marks the archive as modified and saves on close
      def commit
        # Changes are already applied to entries
        # Just mark archive as modified
        archive.instance_variable_set(:@modified, true) if modified?
        @changes = []
        self
      end
    end
  end
end
