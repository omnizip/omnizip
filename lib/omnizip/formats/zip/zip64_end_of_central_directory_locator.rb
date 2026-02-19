# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP64 End of Central Directory Locator
      # Points to the ZIP64 End of Central Directory Record
      class Zip64EndOfCentralDirectoryLocator
        include Constants

        attr_accessor :signature, :disk_number_with_zip64_eocd,
                      :zip64_eocd_offset, :total_disks

        def initialize(
          signature: ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE,
          disk_number_with_zip64_eocd: 0,
          zip64_eocd_offset: 0,
          total_disks: 1
        )
          @signature = signature
          @disk_number_with_zip64_eocd = disk_number_with_zip64_eocd
          @zip64_eocd_offset = zip64_eocd_offset
          @total_disks = total_disks
        end

        # Serialize to binary format
        def to_binary
          [
            signature,
            disk_number_with_zip64_eocd,
            zip64_eocd_offset,
            total_disks,
          ].pack("VVQV")
        end

        # Parse from binary data
        def self.from_binary(data)
          signature, disk_number, offset, total_disks = data.unpack("VVQV")

          unless signature == ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE
            raise Omnizip::FormatError,
                  "Invalid ZIP64 EOCD Locator signature"
          end

          new(
            signature: signature,
            disk_number_with_zip64_eocd: disk_number,
            zip64_eocd_offset: offset,
            total_disks: total_disks,
          )
        end

        # Size of this record in bytes (always 20 bytes)
        def self.record_size
          20
        end

        def record_size
          self.class.record_size
        end
      end
    end
  end
end
