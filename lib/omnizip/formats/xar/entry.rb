# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Xar
      # XAR file entry model
      #
      # Represents a single file/directory/link in a XAR archive.
      # Each entry has metadata and optional data.
      class Entry
        include Constants

        attr_accessor :id, :name, :type, :mode, :uid, :gid, :user, :group,
                      :size, :ctime, :mtime, :atime,
                      :data_offset, :data_length, :data_size, :data_encoding,
                      :archived_checksum, :archived_checksum_style,
                      :extracted_checksum, :extracted_checksum_style,
                      :link_type, :link_target,
                      :device_major, :device_minor,
                      :ino, :nlink, :flags, :ea

        attr_reader :data

        # Extended attributes structure
        class ExtendedAttribute
          include Constants

          attr_accessor :id, :name, :fstype, :data_offset, :data_length,
                        :data_size, :data_encoding, :archived_checksum,
                        :extracted_checksum

          def initialize(name: nil)
            @name = name
            @data_offset = 0
            @data_length = 0
            @data_size = 0
            @data_encoding = COMPRESSION_NONE
          end
        end

        # Initialize entry
        #
        # @param name [String] Entry name/path
        # @param options [Hash] Entry options
        def initialize(name, options = {})
          @id = options[:id]
          @name = name
          @type = options[:type] || TYPE_FILE
          @mode = options[:mode] || 0o644
          @uid = options[:uid] || 0
          @gid = options[:gid] || 0
          @user = options[:user] || ""
          @group = options[:group] || ""
          @size = options[:size] || 0
          @ctime = options[:ctime]
          @mtime = options[:mtime]
          @atime = options[:atime]

          # Data properties
          @data_offset = options[:data_offset] || 0
          @data_length = options[:data_length] || 0
          @data_size = options[:data_size] || 0
          @data_encoding = options[:data_encoding] || COMPRESSION_NONE

          # Checksums
          @archived_checksum = options[:archived_checksum]
          @archived_checksum_style = options[:archived_checksum_style]
          @extracted_checksum = options[:extracted_checksum]
          @extracted_checksum_style = options[:extracted_checksum_style]

          # Links
          @link_type = options[:link_type]
          @link_target = options[:link_target]

          # Devices
          @device_major = options[:device_major]
          @device_minor = options[:device_minor]

          # Other metadata
          @ino = options[:ino]
          @nlink = options[:nlink] || 1
          @flags = options[:flags]
          @ea = options[:ea] || [] # Extended attributes

          @data = nil
        end

        # Set entry data
        #
        # @param data [String] Entry data
        def data=(data)
          @data = data
          @data_size = data&.bytesize || 0
          @size = @data_size
        end

        # Check if entry is a directory
        #
        # @return [Boolean] true if directory
        def directory?
          @type == TYPE_DIRECTORY
        end

        # Check if entry is a regular file
        #
        # @return [Boolean] true if regular file
        def file?
          @type == TYPE_FILE
        end

        # Check if entry is a symbolic link
        #
        # @return [Boolean] true if symbolic link
        def symlink?
          @type == TYPE_SYMLINK
        end

        # Check if entry is a hard link
        #
        # @return [Boolean] true if hard link
        def hardlink?
          @type == TYPE_HARDLINK
        end

        # Check if entry is a device
        #
        # @return [Boolean] true if block or character device
        def device?
          @type == TYPE_BLOCK || @type == TYPE_CHAR
        end

        # Check if entry is a FIFO
        #
        # @return [Boolean] true if FIFO
        def fifo?
          @type == TYPE_FIFO
        end

        # Check if entry is a socket
        #
        # @return [Boolean] true if socket
        def socket?
          @type == TYPE_SOCKET
        end

        # Get file type from mode
        #
        # @return [String] XAR type string
        def self.type_from_mode(mode)
          case mode & 0o170000
          when 0o040000 then TYPE_DIRECTORY
          when 0o100000 then TYPE_FILE
          when 0o120000 then TYPE_SYMLINK
          when 0o060000 then TYPE_BLOCK
          when 0o020000 then TYPE_CHAR
          when 0o010000 then TYPE_FIFO
          when 0o140000 then TYPE_SOCKET
          else TYPE_FILE
          end
        end

        # Convert entry to hash for TOC generation
        #
        # @return [Hash] Entry as hash
        def to_h
          hash = {
            id: @id,
            name: @name,
            type: @type,
          }

          hash[:mode] = format("0%03o", @mode) if @mode
          hash[:uid] = @uid if @uid
          hash[:gid] = @gid if @gid
          hash[:user] = @user unless @user.to_s.empty?
          hash[:group] = @group unless @group.to_s.empty?
          hash[:size] = @size if @size&.positive?

          # Timestamps
          hash[:ctime] = format_timestamp(@ctime) if @ctime
          hash[:mtime] = format_timestamp(@mtime) if @mtime
          hash[:atime] = format_timestamp(@atime) if @atime

          # Data section
          if @data_size&.positive? || file?
            data_hash = {}
            data_hash[:offset] = @data_offset
            data_hash[:size] = @data_length if @data_length&.positive?
            data_hash[:length] = @data_size if @data_size&.positive?

            if @data_encoding && @data_encoding != COMPRESSION_NONE
              data_hash[:encoding] =
                COMPRESSION_MIME_TYPES[@data_encoding] || @data_encoding
            end

            if @archived_checksum
              data_hash[:archived_checksum] =
                @archived_checksum
            end
            if @archived_checksum_style
              data_hash[:archived_checksum_style] =
                @archived_checksum_style
            end
            if @extracted_checksum
              data_hash[:extracted_checksum] =
                @extracted_checksum
            end
            if @extracted_checksum_style
              data_hash[:extracted_checksum_style] =
                @extracted_checksum_style
            end

            hash[:data] = data_hash
          end

          # Links
          if @link_target
            hash[:link] = { type: @link_type, target: @link_target }
          end

          # Devices
          if device?
            device_hash = {}
            device_hash[:major] = @device_major if @device_major
            device_hash[:minor] = @device_minor if @device_minor
            hash[:device] = device_hash
          end

          # Extended attributes
          if @ea&.any?
            hash[:ea] = @ea.map do |attr|
              ea_hash = { name: attr.name }
              ea_hash[:offset] = attr.data_offset
              ea_hash[:size] = attr.data_length
              ea_hash[:length] = attr.data_size
              ea_hash
            end
          end

          hash
        end

        private

        # Format timestamp for TOC
        #
        # @param time [Time] Time object
        # @return [String] Formatted timestamp
        def format_timestamp(time)
          case time
          when Time
            time.to_f.to_s
          when Numeric
            time.to_s
          else
            time.to_s
          end
        end
      end
    end
  end
end
