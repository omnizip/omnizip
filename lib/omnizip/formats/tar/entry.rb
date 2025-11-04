# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Tar
      # TAR entry model
      #
      # Represents a single entry (file, directory, link) in a TAR archive
      class Entry
        include Constants

        attr_accessor :name, :mode, :uid, :gid, :size, :mtime
        attr_accessor :typeflag, :linkname, :uname, :gname
        attr_accessor :devmajor, :devminor, :prefix
        attr_reader :data

        # Initialize a new TAR entry
        #
        # @param name [String] Entry name/path
        # @param options [Hash] Entry options
        def initialize(name, options = {})
          @name = name
          @mode = options[:mode] || 0o644
          @uid = options[:uid] || 0
          @gid = options[:gid] || 0
          @size = options[:size] || 0
          @mtime = options[:mtime] || Time.now
          @typeflag = options[:typeflag] || TYPE_REGULAR
          @linkname = options[:linkname] || ""
          @uname = options[:uname] || ""
          @gname = options[:gname] || ""
          @devmajor = options[:devmajor] || 0
          @devminor = options[:devminor] || 0
          @prefix = options[:prefix] || ""
          @data = nil
        end

        # Set entry data
        #
        # @param data [String] Entry data
        def data=(data)
          @data = data
          @size = data.bytesize if data
        end

        # Check if entry is a directory
        #
        # @return [Boolean] true if directory
        def directory?
          @typeflag == TYPE_DIRECTORY
        end

        # Check if entry is a file
        #
        # @return [Boolean] true if regular file
        def file?
          @typeflag == TYPE_REGULAR || @typeflag.nil? || @typeflag.empty?
        end

        # Check if entry is a symbolic link
        #
        # @return [Boolean] true if symbolic link
        def symlink?
          @typeflag == TYPE_SYMLINK
        end

        # Get full entry name (prefix + name)
        #
        # @return [String] Full entry name
        def full_name
          if @prefix && !@prefix.empty?
            File.join(@prefix, @name)
          else
            @name
          end
        end

        # Calculate checksum for TAR header
        #
        # @param header [String] TAR header bytes
        # @return [Integer] Checksum value
        def self.calculate_checksum(header)
          # Replace checksum field with spaces for calculation
          checksum_header = header.dup
          checksum_header[CHECKSUM_OFFSET, CHECKSUM_SIZE] = " " * CHECKSUM_SIZE

          # Sum all bytes
          checksum_header.bytes.sum
        end
      end
    end
  end
end