# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Cpio
      # CPIO archive entry
      #
      # Represents a file, directory, or special file in a CPIO archive.
      # Supports newc, CRC, and ODC formats.
      class Entry
        include Constants

        # @return [String] Magic number identifying format
        attr_accessor :magic

        # @return [Integer] Inode number
        attr_accessor :ino

        # @return [Integer] File mode and type
        attr_accessor :mode

        # @return [Integer] User ID
        attr_accessor :uid

        # @return [Integer] Group ID
        attr_accessor :gid

        # @return [Integer] Number of hard links
        attr_accessor :nlink

        # @return [Integer] Modification time (Unix timestamp)
        attr_accessor :mtime

        # @return [Integer] File size in bytes
        attr_accessor :filesize

        # @return [Integer] Device major number
        attr_accessor :dev_major

        # @return [Integer] Device minor number
        attr_accessor :dev_minor

        # @return [Integer] Special device major number (for device files)
        attr_accessor :rdev_major

        # @return [Integer] Special device minor number (for device files)
        attr_accessor :rdev_minor

        # @return [Integer] Filename length (including null terminator)
        attr_accessor :namesize

        # @return [Integer] Checksum (CRC format only)
        attr_accessor :checksum

        # @return [String] Entry name/path
        attr_accessor :name

        # @return [String] File data
        attr_accessor :data

        # Initialize CPIO entry
        #
        # @param attributes [Hash] Entry attributes
        def initialize(attributes = {})
          @magic = attributes.fetch(:magic, MAGIC_NEWC)
          @ino = attributes.fetch(:ino, 0)
          @mode = attributes.fetch(:mode, S_IFREG | 0o644)
          @uid = attributes.fetch(:uid, 0)
          @gid = attributes.fetch(:gid, 0)
          @nlink = attributes.fetch(:nlink, 1)
          @mtime = attributes.fetch(:mtime, Time.now.to_i)
          @filesize = attributes.fetch(:filesize, 0)
          @dev_major = attributes.fetch(:dev_major, 0)
          @dev_minor = attributes.fetch(:dev_minor, 0)
          @rdev_major = attributes.fetch(:rdev_major, 0)
          @rdev_minor = attributes.fetch(:rdev_minor, 0)
          @namesize = attributes.fetch(:namesize, 0)
          @checksum = attributes.fetch(:checksum, 0)
          @name = attributes.fetch(:name, "")
          @data = attributes.fetch(:data, "")

          # Auto-calculate namesize if not provided
          @namesize = @name.bytesize + 1 if @namesize.zero? && !@name.empty?
          @filesize = @data.bytesize if @filesize.zero? && !@data.empty?
        end

        # Check if entry is a directory
        #
        # @return [Boolean] true if directory
        def directory?
          (@mode & S_IFMT) == S_IFDIR
        end

        # Check if entry is a regular file
        #
        # @return [Boolean] true if regular file
        def file?
          (@mode & S_IFMT) == S_IFREG
        end

        # Check if entry is a symbolic link
        #
        # @return [Boolean] true if symlink
        def symlink?
          (@mode & S_IFMT) == S_IFLNK
        end

        # Check if entry is a device
        #
        # @return [Boolean] true if device (block or character)
        def device?
          type = @mode & S_IFMT
          type == S_IFBLK || type == S_IFCHR
        end

        # Check if entry is the trailer
        #
        # @return [Boolean] true if trailer entry
        def trailer?
          @name == TRAILER_NAME
        end

        # Convert entry to binary format
        #
        # @param format [Symbol] CPIO format (:newc, :crc, :odc)
        # @return [String] Binary representation
        def to_binary(format: :newc)
          case format
          when :newc, :crc
            to_newc_binary
          when :odc
            to_odc_binary
          else
            raise ArgumentError, "Unsupported CPIO format: #{format}"
          end
        end

        # Convert to newc format binary
        #
        # @return [String] Binary data in newc format
        def to_newc_binary
          # Build header (110 bytes, ASCII hex)
          header = format(
            "%06s%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x",
            @magic,
            @ino & 0xFFFFFFFF,
            @mode & 0xFFFFFFFF,
            @uid & 0xFFFFFFFF,
            @gid & 0xFFFFFFFF,
            @nlink & 0xFFFFFFFF,
            @mtime & 0xFFFFFFFF,
            @filesize & 0xFFFFFFFF,
            @dev_major & 0xFFFFFFFF,
            @dev_minor & 0xFFFFFFFF,
            @rdev_major & 0xFFFFFFFF,
            @rdev_minor & 0xFFFFFFFF,
            @namesize & 0xFFFFFFFF,
            @checksum & 0xFFFFFFFF
          )

          # Assemble complete entry
          result = String.new
          result << header
          result << @name
          result << "\x00"

          # Pad header+name to 4-byte boundary
          header_name_size = header.bytesize + @name.bytesize + 1
          padding = padding_to_align(header_name_size, NEWC_ALIGNMENT)
          result << ("\x00" * padding) if padding > 0

          # Add file data
          result << @data

          # Pad data to 4-byte boundary
          data_padding = padding_to_align(@data.bytesize, NEWC_ALIGNMENT)
          result << ("\x00" * data_padding) if data_padding > 0

          result
        end

        # Convert to ODC format binary
        #
        # @return [String] Binary data in ODC format
        def to_odc_binary
          # ODC format uses 6-character octal fields
          header = format(
            "%06o%06o%06o%06o%06o%06o%06o%06o%011lo%06o%011lo",
            MAGIC_BINARY,
            @dev_major << 8 | @dev_minor,
            @ino & 0o777777,
            @mode & 0o777777,
            @uid & 0o777777,
            @gid & 0o777777,
            @nlink & 0o777777,
            @rdev_major << 8 | @rdev_minor,
            @mtime & 0o77777777777,
            @namesize & 0o777777,
            @filesize & 0o77777777777
          )

          result = String.new
          result << header
          result << @name
          result << "\x00"
          result << @data

          result
        end

        # Parse entry from binary data
        #
        # @param io [IO] Input stream
        # @param format [Symbol, nil] Format hint (:newc, :crc, :odc, nil=auto-detect)
        # @return [Entry] Parsed entry
        def self.parse(io, format: nil)
          # Read magic to detect format
          magic = io.read(6)
          io.seek(-6, IO::SEEK_CUR) # Rewind

          format ||= detect_format(magic)

          case format
          when :newc, :crc
            parse_newc(io)
          when :odc
            parse_odc(io)
          else
            raise "Unknown CPIO format"
          end
        end

        # Detect CPIO format from magic
        #
        # @param magic [String] Magic bytes
        # @return [Symbol] Format type
        def self.detect_format(magic)
          case magic
          when MAGIC_NEWC then :newc
          when MAGIC_CRC then :crc
          when MAGIC_ODC then :odc
          else
            # Try binary format
            magic_int = magic.unpack1("n")
            magic_int == MAGIC_BINARY ? :binary : nil
          end
        end

        # Parse newc format entry
        #
        # @param io [IO] Input stream
        # @return [Entry] Parsed entry
        def self.parse_newc(io)
          header = io.read(NEWC_HEADER_SIZE)
          raise "Truncated CPIO header" unless header && header.bytesize == NEWC_HEADER_SIZE

          # Parse ASCII hex fields
          magic = header[0, 6]
          ino = header[6, 8].to_i(16)
          mode = header[14, 8].to_i(16)
          uid = header[22, 8].to_i(16)
          gid = header[30, 8].to_i(16)
          nlink = header[38, 8].to_i(16)
          mtime = header[46, 8].to_i(16)
          filesize = header[54, 8].to_i(16)
          dev_major = header[62, 8].to_i(16)
          dev_minor = header[70, 8].to_i(16)
          rdev_major = header[78, 8].to_i(16)
          rdev_minor = header[86, 8].to_i(16)
          namesize = header[94, 8].to_i(16)
          checksum = header[102, 8].to_i(16)

          # Read filename
          name_data = io.read(namesize)
          name = name_data.chomp("\x00")

          # Skip padding to 4-byte boundary
          header_name_size = NEWC_HEADER_SIZE + namesize
          padding = padding_to_align(header_name_size, NEWC_ALIGNMENT)
          io.read(padding) if padding > 0

          # Read file data
          data = io.read(filesize)

          # Skip padding to 4-byte boundary
          data_padding = padding_to_align(filesize, NEWC_ALIGNMENT)
          io.read(data_padding) if data_padding > 0

          new(
            magic: magic,
            ino: ino,
            mode: mode,
            uid: uid,
            gid: gid,
            nlink: nlink,
            mtime: mtime,
            filesize: filesize,
            dev_major: dev_major,
            dev_minor: dev_minor,
            rdev_major: rdev_major,
            rdev_minor: rdev_minor,
            namesize: namesize,
            checksum: checksum,
            name: name,
            data: data || ""
          )
        end

        # Parse ODC format entry
        #
        # @param io [IO] Input stream
        # @return [Entry] Parsed entry
        def self.parse_odc(io)
          header = io.read(76)
          raise "Truncated CPIO header" unless header && header.bytesize == 76

          # Parse octal fields
          magic = header[0, 6]
          dev = header[6, 6].to_i(8)
          ino = header[12, 6].to_i(8)
          mode = header[18, 6].to_i(8)
          uid = header[24, 6].to_i(8)
          gid = header[30, 6].to_i(8)
          nlink = header[36, 6].to_i(8)
          rdev = header[42, 6].to_i(8)
          mtime = header[48, 11].to_i(8)
          namesize = header[59, 6].to_i(8)
          filesize = header[65, 11].to_i(8)

          # Extract device numbers
          dev_major = dev >> 8
          dev_minor = dev & 0xFF
          rdev_major = rdev >> 8
          rdev_minor = rdev & 0xFF

          # Read filename
          name_data = io.read(namesize)
          name = name_data.chomp("\x00")

          # Read file data
          data = io.read(filesize)

          new(
            magic: magic,
            ino: ino,
            mode: mode,
            uid: uid,
            gid: gid,
            nlink: nlink,
            mtime: mtime,
            filesize: filesize,
            dev_major: dev_major,
            dev_minor: dev_minor,
            rdev_major: rdev_major,
            rdev_minor: rdev_minor,
            namesize: namesize,
            checksum: 0,
            name: name,
            data: data || ""
          )
        end

        private

        # Calculate padding needed to align to boundary
        #
        # @param size [Integer] Current size
        # @param alignment [Integer] Alignment boundary
        # @return [Integer] Padding bytes needed
        def padding_to_align(size, alignment)
          remainder = size % alignment
          remainder.zero? ? 0 : alignment - remainder
        end

        # Class method for padding calculation
        def self.padding_to_align(size, alignment)
          remainder = size % alignment
          remainder.zero? ? 0 : alignment - remainder
        end
      end
    end
  end
end