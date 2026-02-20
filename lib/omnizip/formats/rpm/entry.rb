# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Rpm
      # RPM file entry
      #
      # Represents a single file within an RPM package.
      # File information is assembled from multiple header tags.
      class Entry
        include Constants

        # @return [String] File path
        attr_accessor :path

        # @return [Integer] File size
        attr_accessor :size

        # @return [Integer] File mode
        attr_accessor :mode

        # @return [Integer] User ID
        attr_accessor :uid

        # @return [Integer] Group ID
        attr_accessor :gid

        # @return [Time] Modification time
        attr_accessor :mtime

        # @return [String] File digest (MD5/SHA)
        attr_accessor :digest

        # @return [String] User name
        attr_accessor :user

        # @return [String] Group name
        attr_accessor :group

        # @return [Integer] File flags
        attr_accessor :flags

        # @return [String] Symlink target (if symlink)
        attr_accessor :link_to

        # Check if entry is a directory
        #
        # @return [Boolean]
        def directory?
          (@mode & 0o170_000) == 0o040_000
        end

        # Check if entry is a regular file
        #
        # @return [Boolean]
        def file?
          (@mode & 0o170_000) == 0o100_000
        end

        # Check if entry is a symbolic link
        #
        # @return [Boolean]
        def symlink?
          (@mode & 0o170_000) == 0o120_000
        end

        # Check if file is a config file
        #
        # @return [Boolean]
        def config?
          @flags.anybits?(FILE_CONFIG)
        end

        # Check if file is documentation
        #
        # @return [Boolean]
        def doc?
          @flags.anybits?(FILE_DOC)
        end

        # Get permission string
        #
        # @return [String] Unix-style permission string
        def permissions
          perms = (@mode & 0o777).to_s(8).rjust(3, "0")

          type_char = if directory?
                        "d"
                      elsif symlink?
                        "l"
                      else
                        "-"
                      end

          "#{type_char}#{perms}"
        end
      end
    end
  end
end
