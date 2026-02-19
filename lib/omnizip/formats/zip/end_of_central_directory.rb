# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Zip
      # ZIP End of Central Directory Record
      class EndOfCentralDirectory
        include Constants

        attr_accessor :signature, :disk_number, :disk_number_with_cd,
                      :total_entries_this_disk, :total_entries,
                      :central_directory_size, :central_directory_offset,
                      :comment_length, :comment

        def initialize(
          signature: END_OF_CENTRAL_DIRECTORY_SIGNATURE,
          disk_number: 0,
          disk_number_with_cd: 0,
          total_entries_this_disk: 0,
          total_entries: 0,
          central_directory_size: 0,
          central_directory_offset: 0,
          comment_length: 0,
          comment: ""
        )
          @signature = signature
          @disk_number = disk_number
          @disk_number_with_cd = disk_number_with_cd
          @total_entries_this_disk = total_entries_this_disk
          @total_entries = total_entries
          @central_directory_size = central_directory_size
          @central_directory_offset = central_directory_offset
          @comment_length = comment_length
          @comment = comment
        end

        # Check if ZIP64 format is needed
        def zip64?
          total_entries == 0xFFFF ||
            central_directory_size == ZIP64_LIMIT ||
            central_directory_offset == ZIP64_LIMIT ||
            disk_number == 0xFFFF ||
            disk_number_with_cd == 0xFFFF
        end

        # Serialize to binary format
        def to_binary
          @comment_length = comment.bytesize

          [
            signature,
            disk_number,
            disk_number_with_cd,
            total_entries_this_disk,
            total_entries,
            central_directory_size,
            central_directory_offset,
            comment_length,
          ].pack("VvvvvVVv") +
            comment.b
        end

        # Parse from binary data
        def self.from_binary(data)
          signature, disk_number, disk_number_with_cd,
          total_entries_this_disk, total_entries,
          central_directory_size, central_directory_offset,
          comment_length = data.unpack("VvvvvVVv")

          unless signature == END_OF_CENTRAL_DIRECTORY_SIGNATURE
            raise Omnizip::FormatError,
                  "Invalid EOCD signature"
          end

          comment = data[22, comment_length].to_s.force_encoding("UTF-8")

          new(
            signature: signature,
            disk_number: disk_number,
            disk_number_with_cd: disk_number_with_cd,
            total_entries_this_disk: total_entries_this_disk,
            total_entries: total_entries,
            central_directory_size: central_directory_size,
            central_directory_offset: central_directory_offset,
            comment_length: comment_length,
            comment: comment,
          )
        end

        # Size of the record in bytes
        def record_size
          22 + comment_length
        end

        # Find EOCD record by scanning backwards from end of file
        def self.find_in_file(io)
          # Start from the end and work backwards
          # EOCD is at least 22 bytes, can be up to 22 + MAX_COMMENT_LENGTH
          io.seek(0, ::IO::SEEK_END)
          file_size = io.pos

          # Start searching from the end
          max_comment_size = [file_size - 22, MAX_COMMENT_LENGTH].min
          search_start = [file_size - 22 - max_comment_size, 0].max

          io.seek(search_start, ::IO::SEEK_SET)
          buffer = io.read(file_size - search_start)

          # Search for EOCD signature from the end
          signature_bytes = [END_OF_CENTRAL_DIRECTORY_SIGNATURE].pack("V")

          (buffer.size - 22).downto(0) do |i|
            if buffer[i, 4] == signature_bytes
              # Found potential EOCD
              eocd_data = buffer[i..]
              comment_length = eocd_data[20, 2].unpack1("v")

              # Verify this is the actual EOCD by checking if comment length matches
              if i + 22 + comment_length == buffer.size
                return from_binary(eocd_data)
              end
            end
          end

          raise Omnizip::FormatError,
                "Could not find End of Central Directory record"
        end
      end
    end
  end
end
