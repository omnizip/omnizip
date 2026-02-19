# frozen_string_literal: true

module Omnizip
  module LinkHandler
    # Model for hard links
    class HardLink
      attr_reader :target, :path, :inode

      def initialize(target:, path: nil, inode: nil)
        @target = target
        @path = path
        @inode = inode
      end

      # Create the hard link on the filesystem
      def create(link_path)
        LinkHandler.create_hardlink(@target, link_path)
      end

      # Serialize for archive storage
      def serialize
        {
          target: @target,
          inode: @inode,
        }
      end

      # Deserialize from archive storage
      def self.deserialize(data, path: nil)
        if data.is_a?(Hash)
          new(
            target: data[:target] || data["target"],
            path: path,
            inode: data[:inode] || data["inode"],
          )
        else
          # Legacy format: just the target path
          new(target: data, path: path)
        end
      end

      # Check if this is a symbolic link
      def symlink?
        false
      end

      # Check if this is a hard link
      def hardlink?
        true
      end

      # Get the link type as string
      def link_type
        "hardlink"
      end

      # Convert to hash representation
      def to_h
        {
          type: :hardlink,
          target: @target,
          path: @path,
          inode: @inode,
        }
      end

      # String representation
      def to_s
        "#{@path} -> #{@target} (hard link)"
      end

      # Inspect representation
      def inspect
        "#<Omnizip::LinkHandler::HardLink target=#{@target.inspect} " \
          "path=#{@path.inspect} inode=#{@inode}>"
      end
    end
  end
end
