# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP64 End of Central Directory Record
      # Used when the archive exceeds ZIP format limits (>4GB or >65535 entries)
      class Zip64EndOfCentralDirectory
        include Constants

        attr_accessor :signature, :record_size, :version_made_by, :version_needed,
                      :disk_number, :disk_number_with_cd,
                      :total_entries_this_disk, :total_entries,
                      :central_directory_size, :central_directory_offset,
                      :extensible_data_sector

        def initialize(
          signature: ZIP64_END_OF_CENTRAL_DIRECTORY_SIGNATURE,
          record_size: 44, # Size of remaining record (not including signature and size field)
          version_made_by: VERSION_MADE_BY_UNIX | VERSION_ZIP64,
          version_needed: VERSION_ZIP64,
          disk_number: 0,
          disk_number_with_cd: 0,
          total_entries_this_disk: 0,
          total_entries: 0,
          central_directory_size: 0,
          central_directory_offset: 0,
          extensible_data_sector: ""
        )
          @signature = signature
          @record_size = record_size
          @version_made_by = version_made_by
          @version_needed = version_needed
          @disk_number = disk_number
          @disk_number_with_cd = disk_number_with_cd
          @total_entries_this_disk = total_entries_this_disk
          @total_entries = total_entries
          @central_directory_size = central_directory_size
          @central_directory_offset = central_directory_offset
          @extensible_data_sector = extensible_data_sector
        end

        # Serialize to binary format
        def to_binary
          @record_size = 44 + extensible_data_sector.bytesize

          [
            signature,
            record_size,
            version_made_by,
            version_needed,
            disk_number,
            disk_number_with_cd,
            total_entries_this_disk,
            total_entries,
            central_directory_size,
            central_directory_offset,
          ].pack("VQvvVVQQQQ") + extensible_data_sector.b
        end

        # Parse from binary data
        def self.from_binary(data)
          signature, record_size, version_made_by, version_needed,
          disk_number, disk_number_with_cd,
          total_entries_this_disk, total_entries,
          central_directory_size, central_directory_offset = data.unpack("VQvvVVQQQQ")

          unless signature == ZIP64_END_OF_CENTRAL_DIRECTORY_SIGNATURE
            raise Omnizip::FormatError,
                  "Invalid ZIP64 EOCD signature"
          end

          # Extensible data sector starts after the fixed 56 bytes (4+8+2+2+4+4+8+8+8+8)
          extensible_data_sector = if data.bytesize > 56
                                     data[56..]
                                   else
                                     ""
                                   end

          new(
            signature: signature,
            record_size: record_size,
            version_made_by: version_made_by,
            version_needed: version_needed,
            disk_number: disk_number,
            disk_number_with_cd: disk_number_with_cd,
            total_entries_this_disk: total_entries_this_disk,
            total_entries: total_entries,
            central_directory_size: central_directory_size,
            central_directory_offset: central_directory_offset,
            extensible_data_sector: extensible_data_sector,
          )
        end

        # Total size of this record in bytes
        def total_size
          12 + record_size # 4 (signature) + 8 (record_size) + record_size
        end
      end
    end
  end
end
