# frozen_string_literal: true

require_relative "link_handler/symbolic_link"
require_relative "link_handler/hard_link"

module Omnizip
  # Handles symbolic and hard link operations with platform detection
  module LinkHandler
    class << self
      # Check if the platform supports symbolic links
      def supported?
        !windows_platform?
      end

      # Check if symbolic links are supported
      def symlink_supported?
        File.respond_to?(:symlink) && supported?
      end

      # Check if hard links are supported
      def hardlink_supported?
        File.respond_to?(:link) && supported?
      end

      # Detect if a path is a symbolic link
      def symlink?(path)
        return false unless symlink_supported?

        File.symlink?(path)
      rescue StandardError
        false
      end

      # Detect if a path is a hard link
      def hardlink?(path)
        return false unless hardlink_supported?
        return false unless File.exist?(path)
        return false if File.directory?(path)

        stat = File.stat(path)
        stat.nlink > 1
      rescue StandardError
        false
      end

      # Detect the type of link (or nil if not a link)
      def detect_link(path)
        return nil unless supported?
        return :symlink if symlink?(path)
        return :hardlink if hardlink?(path)

        nil
      end

      # Create a symbolic link
      def create_symlink(target, link_path)
        unless symlink_supported?
          raise Omnizip::Error,
                "Symbolic links are not supported on #{RUBY_PLATFORM}"
        end

        FileUtils.mkdir_p(File.dirname(link_path))
        File.symlink(target, link_path)
      end

      # Create a hard link
      def create_hardlink(target, link_path)
        unless hardlink_supported?
          raise Omnizip::Error,
                "Hard links are not supported on #{RUBY_PLATFORM}"
        end

        FileUtils.mkdir_p(File.dirname(link_path))
        File.link(target, link_path)
      end

      # Read the target of a symbolic link
      def read_link_target(link_path)
        unless symlink_supported?
          raise Omnizip::Error,
                "Symbolic links are not supported on #{RUBY_PLATFORM}"
        end

        File.readlink(link_path)
      end

      # Get inode number for hard link tracking
      def inode_number(path)
        return nil unless hardlink_supported?
        return nil unless File.exist?(path)

        File.stat(path).ino
      rescue StandardError
        nil
      end

      # Create a SymbolicLink instance from a filesystem path
      def symbolic_link_from_path(path)
        return nil unless symlink?(path)

        target = read_link_target(path)
        SymbolicLink.new(target: target, path: path)
      end

      # Create a HardLink instance from a filesystem path
      def hard_link_from_path(path, original_path)
        return nil unless hardlink?(path)

        HardLink.new(
          target: original_path,
          path: path,
          inode: inode_number(path),
        )
      end

      private

      # Check if running on Windows platform
      def windows_platform?
        RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)
      end
    end
  end
end
