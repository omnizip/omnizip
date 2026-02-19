# frozen_string_literal: true

module Omnizip
  # Platform detection and capabilities
  # Provides cross-platform compatibility checks
  module Platform
    # Detect if running on Windows
    #
    # @return [Boolean] true if Windows
    def self.windows?
      !!(RUBY_PLATFORM =~ /mswin|mingw|cygwin/)
    end

    # Detect if running on macOS
    #
    # @return [Boolean] true if macOS
    def self.macos?
      !!RUBY_PLATFORM.include?("darwin")
    end

    # Detect if running on Linux
    #
    # @return [Boolean] true if Linux
    def self.linux?
      !!RUBY_PLATFORM.include?("linux")
    end

    # Detect if running on Unix-like system
    #
    # @return [Boolean] true if Unix-like (macOS, Linux, BSD, etc.)
    def self.unix?
      !windows?
    end

    # Get platform name
    #
    # @return [String] Platform name
    def self.name
      return "Windows" if windows?
      return "macOS" if macos?
      return "Linux" if linux?

      "Unknown"
    end

    # Check if NTFS alternate streams are supported
    # Only available on Windows with NTFS filesystem
    #
    # @return [Boolean] true if NTFS streams supported
    def self.supports_ntfs_streams?
      windows?
    end

    # Check if symbolic links are supported
    #
    # @return [Boolean] true if symlinks supported
    def self.supports_symlinks?
      unix? || (windows? && windows_developer_mode?)
    end

    # Check if hard links are supported
    #
    # @return [Boolean] true if hard links supported
    def self.supports_hardlinks?
      true # Supported on all modern platforms
    end

    # Check if extended attributes are supported
    #
    # @return [Boolean] true if xattrs supported
    def self.supports_extended_attributes?
      unix?
    end

    # Check if file permissions are supported
    #
    # @return [Boolean] true if POSIX permissions supported
    def self.supports_file_permissions?
      unix?
    end

    # Get platform-specific features
    #
    # @return [Hash] Feature flags
    def self.features
      {
        ntfs_streams: supports_ntfs_streams?,
        symlinks: supports_symlinks?,
        hardlinks: supports_hardlinks?,
        extended_attributes: supports_extended_attributes?,
        file_permissions: supports_file_permissions?,
      }
    end

    # Check Windows Developer Mode (for symlink support)
    #
    # @return [Boolean] true if developer mode enabled
    def self.windows_developer_mode?
      return false unless windows?

      # Check registry for developer mode setting
      # HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock
      # AllowDevelopmentWithoutDevLicense = 1
      begin
        require "win32/registry"
        Win32::Registry::HKEY_LOCAL_MACHINE.open(
          'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
          Win32::Registry::KEY_READ,
        ) do |reg|
          value = reg["AllowDevelopmentWithoutDevLicense"]
          return value == 1
        end
      rescue LoadError, StandardError
        # win32/registry not available or key doesn't exist
        false
      end
    end

    # Get file system type for a path
    #
    # @param path [String] File or directory path
    # @return [String, nil] Filesystem type or nil if unknown
    def self.filesystem_type(path)
      return nil unless File.exist?(path)

      if windows?
        detect_windows_filesystem(path)
      elsif macos?
        detect_macos_filesystem(path)
      elsif linux?
        detect_linux_filesystem(path)
      end
    end

    # Check if path is on NTFS filesystem
    #
    # @param path [String] File or directory path
    # @return [Boolean] true if NTFS
    def self.ntfs?(path)
      filesystem_type(path)&.upcase == "NTFS"
    end

    # Detect Windows filesystem type
    #
    # @param path [String] Path
    # @return [String, nil] Filesystem type
    def self.detect_windows_filesystem(path)
      # Get drive letter
      drive = File.expand_path(path)[0, 2]
      return nil unless drive =~ /^[A-Za-z]:$/

      # Use fsutil to get filesystem type
      output = `fsutil fsinfo volumeinfo #{drive} 2>&1`
      Regexp.last_match(1) if output =~ /File System Name\s*:\s*(\w+)/i
    rescue StandardError
      nil
    end

    # Detect macOS filesystem type
    #
    # @param path [String] Path
    # @return [String, nil] Filesystem type
    def self.detect_macos_filesystem(path)
      output = `df -T #{path} 2>&1`.lines.last
      return nil unless output

      # Format: filesystem type blocks used avail capacity mounted
      parts = output.split
      parts[1] if parts.size > 1
    rescue StandardError
      nil
    end

    # Detect Linux filesystem type
    #
    # @param path [String] Path
    # @return [String, nil] Filesystem type
    def self.detect_linux_filesystem(path)
      output = `df -T #{path} 2>&1`.lines.last
      return nil unless output

      # Format: filesystem type blocks used avail use% mounted
      parts = output.split
      parts[1] if parts.size > 1
    rescue StandardError
      nil
    end
  end
end
