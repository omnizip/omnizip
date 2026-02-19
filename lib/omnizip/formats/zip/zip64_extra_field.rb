# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP64 Extended Information Extra Field
      # Used in local/central headers when sizes exceed 32-bit limits
      class Zip64ExtraField
        include Constants

        attr_accessor :tag, :size, :uncompressed_size, :compressed_size,
                      :relative_header_offset, :disk_start_number

        def initialize(
          tag: ZIP64_EXTRA_FIELD_TAG,
          uncompressed_size: nil,
          compressed_size: nil,
          relative_header_offset: nil,
          disk_start_number: nil
        )
          @tag = tag
          @uncompressed_size = uncompressed_size
          @compressed_size = compressed_size
          @relative_header_offset = relative_header_offset
          @disk_start_number = disk_start_number
          @size = calculate_size
        end

        # Serialize to binary format
        def to_binary
          @size = calculate_size
          data = [tag, size].pack("vv")

          # Fields are included in the order they're needed
          # based on which values in the regular header are 0xFFFFFFFF
          data << [uncompressed_size].pack("Q") if uncompressed_size
          data << [compressed_size].pack("Q") if compressed_size
          data << [relative_header_offset].pack("Q") if relative_header_offset
          data << [disk_start_number].pack("V") if disk_start_number

          data
        end

        # Parse from binary data
        # needs_uncompressed, needs_compressed, needs_offset, needs_disk specify
        # which fields should be present based on the regular header values
        def self.from_binary(data, needs_uncompressed: false, needs_compressed: false,
                            needs_offset: false, needs_disk: false)
          tag, = data.unpack("vv")

          unless tag == ZIP64_EXTRA_FIELD_TAG
            raise Omnizip::FormatError,
                  "Invalid ZIP64 extra field tag"
          end

          offset = 4 # After tag and size
          uncompressed_size = nil
          compressed_size = nil
          relative_header_offset = nil
          disk_start_number = nil

          # Read fields in order based on what's needed
          if needs_uncompressed && offset + 8 <= data.bytesize
            uncompressed_size = data[offset, 8].unpack1("Q")
            offset += 8
          end

          if needs_compressed && offset + 8 <= data.bytesize
            compressed_size = data[offset, 8].unpack1("Q")
            offset += 8
          end

          if needs_offset && offset + 8 <= data.bytesize
            relative_header_offset = data[offset, 8].unpack1("Q")
            offset += 8
          end

          if needs_disk && offset + 4 <= data.bytesize
            disk_start_number = data[offset, 4].unpack1("V")
          end

          new(
            tag: tag,
            uncompressed_size: uncompressed_size,
            compressed_size: compressed_size,
            relative_header_offset: relative_header_offset,
            disk_start_number: disk_start_number,
          )
        end

        # Check if this extra field is needed
        def self.needed?(uncompressed_size: 0, compressed_size: 0, offset: 0)
          uncompressed_size >= ZIP64_LIMIT ||
            compressed_size >= ZIP64_LIMIT ||
            offset >= ZIP64_LIMIT
        end

        private

        # Calculate the size field value
        def calculate_size
          size = 0
          size += 8 if uncompressed_size
          size += 8 if compressed_size
          size += 8 if relative_header_offset
          size += 4 if disk_start_number
          size
        end
      end
    end
  end
end
