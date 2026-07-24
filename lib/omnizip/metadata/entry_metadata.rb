# frozen_string_literal: true

module Omnizip
  module Metadata
    # Model for file entry metadata
    # Wraps CentralDirectoryHeader with a cleaner metadata API
    class EntryMetadata
      attr_reader :entry

      # Initialize metadata for an entry
      # @param entry [Omnizip::Zip::Entry] The entry to manage metadata for
      def initialize(entry)
        @entry = entry
        @modified = false
      end

      # Get entry comment
      # @return [String] Entry comment
      def comment
        entry.comment
      end

      # Set entry comment
      # @param value [String] New comment
      def comment=(value)
        entry.comment = value.to_s
        @modified = true
      end

      # Get modification time
      # @return [Time] Modification time
      def mtime
        entry.time
      end

      # Set modification time
      # @param value [Time] New modification time
      def mtime=(value)
        unless value.is_a?(Time)
          raise ArgumentError,
                "mtime must be a Time object"
        end

        entry.header.last_mod_time = dos_time(value)
        entry.header.last_mod_date = dos_date(value)
        @modified = true
      end

      # Get Unix permissions
      # @return [Integer] Unix permissions (e.g., 0644)
      def unix_permissions
        entry.unix_perms
      end

      # Set Unix permissions
      # @param perms [Integer] Unix permissions (e.g., 0644, 0755)
      def unix_permissions=(perms)
        unless perms.is_a?(Integer)
          raise ArgumentError,
                "permissions must be an integer"
        end
        unless (0..0o777).cover?(perms)
          raise ArgumentError,
                "permissions out of range"
        end

        entry.unix_perms = perms
        @modified = true
      end

      # Get external attributes
      # @return [Integer] External attributes
      def attributes
        entry.header.external_attributes
      end

      # Set external attributes
      # @param value [Integer, Symbol] External attributes or symbol like :readonly
      def attributes=(value)
        case value
        when Integer
          entry.header.external_attributes = value
        when Symbol
          set_attribute_flag(value)
        else
          raise ArgumentError, "attributes must be Integer or Symbol"
        end
        @modified = true
      end

      # Check if metadata has been modified
      # @return [Boolean] True if modified
      def modified?
        @modified
      end

      # Reset modified flag
      def reset_modified
        @modified = false
      end

      # Get all metadata as a hash
      # @return [Hash] Metadata hash
      def to_h
        {
          name: entry.name,
          comment: comment,
          mtime: mtime,
          unix_permissions: unix_permissions,
          size: entry.size,
          compressed_size: entry.compressed_size,
          crc: entry.crc,
          directory: entry.directory?,
        }
      end

      private

      # Set attribute flag
      def set_attribute_flag(flag)
        case flag
        when :readonly
          entry.header.external_attributes |= 0x01
        when :hidden
          entry.header.external_attributes |= 0x02
        when :system
          entry.header.external_attributes |= 0x04
        when :archive
          entry.header.external_attributes |= 0x20
        else
          raise ArgumentError, "Unknown attribute flag: #{flag}"
        end
      end

      # Convert Time to DOS time format
      def dos_time(time)
        ((time.hour << 11) | (time.min << 5) | (time.sec / 2)) & 0xFFFF
      end

      # Convert Time to DOS date format
      def dos_date(time)
        (((time.year - 1980) << 9) | (time.month << 5) | time.day) & 0xFFFF
      end
    end
  end
end
