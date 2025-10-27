# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP Central Directory File Header
      class CentralDirectoryHeader
        include Constants

        attr_accessor :signature, :version_made_by, :version_needed, :flags,
                      :compression_method, :last_mod_time, :last_mod_date,
                      :crc32, :compressed_size, :uncompressed_size,
                      :filename_length, :extra_field_length, :comment_length,
                      :disk_number_start, :internal_attributes, :external_attributes,
                      :local_header_offset, :filename, :extra_field, :comment

        def initialize(
          signature: CENTRAL_DIRECTORY_SIGNATURE,
          version_made_by: VERSION_MADE_BY_UNIX,
          version_needed: VERSION_DEFAULT,
          flags: 0,
          compression_method: COMPRESSION_STORE,
          last_mod_time: 0,
          last_mod_date: 0,
          crc32: 0,
          compressed_size: 0,
          uncompressed_size: 0,
          filename_length: 0,
          extra_field_length: 0,
          comment_length: 0,
          disk_number_start: 0,
          internal_attributes: 0,
          external_attributes: 0,
          local_header_offset: 0,
          filename: "",
          extra_field: "",
          comment: ""
        )
          @signature = signature
          @version_made_by = version_made_by
          @version_needed = version_needed
          @flags = flags
          @compression_method = compression_method
          @last_mod_time = last_mod_time
          @last_mod_date = last_mod_date
          @crc32 = crc32
          @compressed_size = compressed_size
          @uncompressed_size = uncompressed_size
          @filename_length = filename_length
          @extra_field_length = extra_field_length
          @comment_length = comment_length
          @disk_number_start = disk_number_start
          @internal_attributes = internal_attributes
          @external_attributes = external_attributes
          @local_header_offset = local_header_offset
          @filename = filename
          @extra_field = extra_field
          @comment = comment
        end

        # Check if this is a directory entry
        def directory?
          filename.end_with?("/") ||
            (external_attributes & ATTR_DIRECTORY) != 0
        end

        # Check if ZIP64 format is needed
        def zip64?
          compressed_size == ZIP64_LIMIT ||
            uncompressed_size == ZIP64_LIMIT ||
            local_header_offset == ZIP64_LIMIT ||
            disk_number_start == 0xFFFF
        end

        # Check if entry is encrypted
        def encrypted?
          (flags & FLAG_ENCRYPTED) != 0
        end

        # Check if UTF-8 encoding is used
        def utf8?
          (flags & FLAG_UTF8) != 0
        end

        # Get Unix permissions from external attributes
        def unix_permissions
          (external_attributes >> 16) & 0xFFFF
        end

        # Set Unix permissions in external attributes
        def unix_permissions=(perms)
          @external_attributes = (perms << 16) | (external_attributes & 0xFFFF)
        end

        # Serialize to binary format
        def to_binary
          @filename_length = filename.bytesize
          @extra_field_length = extra_field.bytesize
          @comment_length = comment.bytesize

          [
            signature,
            version_made_by,
            version_needed,
            flags,
            compression_method,
            last_mod_time,
            last_mod_date,
            crc32,
            compressed_size,
            uncompressed_size,
            filename_length,
            extra_field_length,
            comment_length,
            disk_number_start,
            internal_attributes,
            external_attributes,
            local_header_offset,
          ].pack("VvvvvvvVVVvvvvvVV") +
            filename.b +
            extra_field.b +
            comment.b
        end

        # Parse from binary data
        def self.from_binary(data)
          signature, version_made_by, version_needed, flags,
          compression_method, last_mod_time, last_mod_date,
          crc32, compressed_size, uncompressed_size,
          filename_length, extra_field_length, comment_length,
          disk_number_start, internal_attributes,
          external_attributes, local_header_offset = data.unpack("VvvvvvvVVVvvvvvVV")

          raise Omnizip::FormatError, "Invalid central directory signature" unless signature == CENTRAL_DIRECTORY_SIGNATURE

          offset = 46
          filename = data[offset, filename_length].force_encoding("UTF-8")
          offset += filename_length

          extra_field = data[offset, extra_field_length]
          offset += extra_field_length

          comment = data[offset, comment_length].force_encoding("UTF-8")

          new(
            signature: signature,
            version_made_by: version_made_by,
            version_needed: version_needed,
            flags: flags,
            compression_method: compression_method,
            last_mod_time: last_mod_time,
            last_mod_date: last_mod_date,
            crc32: crc32,
            compressed_size: compressed_size,
            uncompressed_size: uncompressed_size,
            filename_length: filename_length,
            extra_field_length: extra_field_length,
            comment_length: comment_length,
            disk_number_start: disk_number_start,
            internal_attributes: internal_attributes,
            external_attributes: external_attributes,
            local_header_offset: local_header_offset,
            filename: filename,
            extra_field: extra_field,
            comment: comment
          )
        end

        # Size of the header in bytes
        def header_size
          46 + filename_length + extra_field_length + comment_length
        end
      end
    end
  end
end