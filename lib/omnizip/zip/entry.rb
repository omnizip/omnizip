# frozen_string_literal: true

require_relative "../formats/zip/central_directory_header"

module Omnizip
  module Zip
    # Rubyzip-compatible Entry class
    # Wraps CentralDirectoryHeader with rubyzip API
    class Entry
      attr_reader :header, :ftype, :filepath

      # Create entry from CentralDirectoryHeader
      def initialize(header, filepath: nil)
        @header = header
        @filepath = filepath
        @ftype = header.directory? ? :directory : :file
      end

      # Entry name (path within archive)
      def name
        header.filename
      end

      # Uncompressed size
      def size
        header.uncompressed_size
      end

      # Compressed size
      def compressed_size
        header.compressed_size
      end

      # CRC32 checksum
      def crc
        header.crc32
      end

      # Compression method ID
      def compression_method
        header.compression_method
      end

      # Modification time
      def time
        dos_time_to_time(header.last_mod_date, header.last_mod_time)
      end

      # Is this a directory?
      def directory?
        @ftype == :directory
      end
      alias_method :is_directory, :directory?

      # Is this a file?
      def file?
        @ftype == :file
      end

      # Is this a symbolic link?
      def symlink?
        false # Not supported yet
      end

      # Get comment
      def comment
        header.comment || ""
      end

      # Set comment
      def comment=(value)
        header.comment = value
      end

      # Get extra field
      def extra
        header.extra_field || ""
      end

      # Set extra field
      def extra=(value)
        header.extra_field = value
      end

      # Unix permissions
      def unix_perms
        header.unix_permissions
      end

      # Set Unix permissions
      def unix_perms=(perms)
        header.unix_permissions = perms
      end

      # Extract this entry to a destination path
      # Note: This requires access to the archive file
      def extract(dest_path, &on_exists_proc)
        raise NotImplementedError, "Entry#extract requires File context. Use Omnizip::Zip::File#extract instead"
      end

      # Get input stream for this entry
      # Note: This requires access to the archive file
      def get_input_stream
        raise NotImplementedError, "Entry#get_input_stream requires File context"
      end

      # String representation
      def to_s
        name
      end

      # Equality comparison
      def ==(other)
        return false unless other.is_a?(Entry)
        name == other.name
      end

      private

      # Convert DOS date/time to Ruby Time
      def dos_time_to_time(dos_date, dos_time)
        return Time.now if dos_date.zero? && dos_time.zero?

        year = ((dos_date >> 9) & 0x7F) + 1980
        month = (dos_date >> 5) & 0x0F
        day = dos_date & 0x1F

        hour = (dos_time >> 11) & 0x1F
        min = (dos_time >> 5) & 0x3F
        sec = (dos_time & 0x1F) * 2

        Time.new(year, month, day, hour, min, sec)
      rescue ArgumentError
        Time.now
      end
    end
  end
end