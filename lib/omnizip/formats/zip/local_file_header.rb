# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP Local File Header
      class LocalFileHeader
        include Constants

        attr_accessor :signature, :version_needed, :flags, :compression_method,
                      :last_mod_time, :last_mod_date, :crc32,
                      :compressed_size, :uncompressed_size,
                      :filename_length, :extra_field_length,
                      :filename, :extra_field

        def initialize(
          signature: LOCAL_FILE_HEADER_SIGNATURE,
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
          filename: "",
          extra_field: ""
        )
          @signature = signature
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
          @filename = filename
          @extra_field = extra_field
        end

        # Check if this is a directory entry
        def directory?
          filename.end_with?("/")
        end

        # Check if ZIP64 format is needed
        def zip64?
          compressed_size == ZIP64_LIMIT ||
            uncompressed_size == ZIP64_LIMIT
        end

        # Check if entry is encrypted
        def encrypted?
          (flags & FLAG_ENCRYPTED) != 0
        end

        # Check if data descriptor follows
        def has_data_descriptor?
          (flags & FLAG_DATA_DESCRIPTOR) != 0
        end

        # Check if UTF-8 encoding is used
        def utf8?
          (flags & FLAG_UTF8) != 0
        end

        # Serialize to binary format
        def to_binary
          @filename_length = filename.bytesize
          @extra_field_length = extra_field.bytesize

          [
            signature,
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
          ].pack("VvvvvvVVVvv") +
            filename.b +
            extra_field.b
        end

        # Parse from binary data
        def self.from_binary(data)
          signature, version_needed, flags, compression_method,
          last_mod_time, last_mod_date, crc32,
          compressed_size, uncompressed_size,
          filename_length, extra_field_length = data.unpack("VvvvvvVVVvv")

          raise Omnizip::FormatError, "Invalid local file header signature" unless signature == LOCAL_FILE_HEADER_SIGNATURE

          offset = 30
          filename = data[offset, filename_length].force_encoding("UTF-8")
          offset += filename_length

          extra_field = data[offset, extra_field_length]

          new(
            signature: signature,
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
            filename: filename,
            extra_field: extra_field
          )
        end

        # Size of the header in bytes
        def header_size
          30 + filename_length + extra_field_length
        end
      end
    end
  end
end