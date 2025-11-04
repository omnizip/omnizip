# frozen_string_literal: true

module Omnizip
  module LinkHandler
    # Model for symbolic links
    class SymbolicLink
      attr_reader :target, :path

      # Unix permissions for symbolic links (0120777)
      SYMLINK_PERMISSIONS = 0o120777

      def initialize(target:, path: nil)
        @target = target
        @path = path
      end

      # Create the symbolic link on the filesystem
      def create(link_path)
        LinkHandler.create_symlink(@target, link_path)
      end

      # Get Unix permissions for symbolic links
      def permissions
        SYMLINK_PERMISSIONS
      end

      # Serialize for archive storage (returns the target path)
      def serialize
        @target
      end

      # Deserialize from archive storage
      def self.deserialize(target_data, path: nil)
        new(target: target_data, path: path)
      end

      # Check if this is a symbolic link
      def symlink?
        true
      end

      # Check if this is a hard link
      def hardlink?
        false
      end

      # Get the link type as string
      def link_type
        "symlink"
      end

      # Convert to hash representation
      def to_h
        {
          type: :symlink,
          target: @target,
          path: @path,
          permissions: permissions
        }
      end

      # String representation
      def to_s
        "#{@path} -> #{@target} (symlink)"
      end

      # Inspect representation
      def inspect
        "#<Omnizip::LinkHandler::SymbolicLink target=#{@target.inspect} " \
          "path=#{@path.inspect}>"
      end
    end
  end
end
