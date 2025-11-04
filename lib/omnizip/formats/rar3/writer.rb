# frozen_string_literal: true

require "lutaml/model"
require "stringio"
require_relative "../rar/rar_format_base"
require_relative "compressor"

module Omnizip
  module Formats
    module Rar3
      # RAR v3 archive writer
      #
      # Writes RAR 3.x format archives, creating headers and compressing file
      # data according to the RAR v3 specification.
      #
      # @example Writing a RAR3 archive
      #   writer = Rar3::Writer.new
      #   File.open("archive.rar", "wb") do |file|
      #     entries = [
      #       {name: "file.txt", data: "content", time: Time.now}
      #     ]
      #     writer.write_archive(file, entries)
      #   end
      class Writer < Rar::RarFormatBase
        # Initialize a RAR v3 writer
        def initialize
          super("rar3")
          @compressor = Compressor.new
        end

        # Write a RAR v3 archive
        #
        # @param io [IO] The output stream
        # @param entries [Array<Hash>] The entries to write
        # @return [void]
        def write_archive(io, entries)
          # Write marker block
          write_marker_block(io)

          # Write archive header
          write_archive_header(io)

          # Write file entries
          entries.each do |entry|
            write_file_entry(io, entry)
          end

          # Write terminator block
          write_terminator_block(io)
        end

        private

        # Write marker block (RAR signature)
        #
        # @param io [IO] The output stream
        # @return [void]
        def write_marker_block(io)
          io.write(spec.magic_bytes.pack("C*"))
        end

        # Write archive header block
        #
        # @param io [IO] The output stream
        # @return [void]
        def write_archive_header(io)
          flags = 0
          # Set default flags if needed

          header_data = StringIO.new
          # Reserved fields
          header_data.write([0, 0].pack("vv"))

          header = create_block_header(
            type: block_type_code(:archive),
            flags: flags,
            data: header_data.string
          )

          write_block_header(io, header)
          io.write(header_data.string)
        end

        # Write a file entry
        #
        # @param io [IO] The output stream
        # @param entry [Hash] The entry data
        # @return [void]
        def write_file_entry(io, entry)
          name = entry[:name] || entry["name"]
          data = entry[:data] || entry["data"]
          mtime = entry[:time] || entry["time"] || Time.now
          method = entry[:method] || entry["method"] || :normal

          # Compress data
          compressed_data = @compressor.compress(data, method: method)

          # Calculate sizes and CRC
          packed_size = compressed_data.bytesize
          unpacked_size = data.bytesize
          file_crc = calculate_crc32(data)

          # Encode filename
          name_bytes = name.encode("UTF-8")
          name_size = name_bytes.bytesize

          # Set flags
          flags = spec.format.file_flags[:unicode]
          if unpacked_size > 0xFFFFFFFF
            flags |= spec.format.file_flags[:large_file]
          end

          # Build file header data
          header_data = StringIO.new
          header_data.write([packed_size & 0xFFFFFFFF].pack("V"))
          header_data.write([unpacked_size & 0xFFFFFFFF].pack("V"))
          header_data.write([spec.format.host_os[:win32]].pack("C"))
          header_data.write([file_crc].pack("V"))
          header_data.write([encode_dos_time(mtime)].pack("V"))
          header_data.write([0x14].pack("C"))  # Version needed
          header_data.write([compression_method_code(method)].pack("C"))
          header_data.write([name_size].pack("v"))
          header_data.write([0x20].pack("V"))  # File attributes
          header_data.write(name_bytes)

          # Add high size fields if needed
          if flags & spec.format.file_flags[:large_file] != 0
            header_data.write([(packed_size >> 32) & 0xFFFFFFFF].pack("V"))
            header_data.write([(unpacked_size >> 32) & 0xFFFFFFFF].pack("V"))
          end

          # Create and write block header
          header = create_block_header(
            type: block_type_code(:file),
            flags: flags,
            data: header_data.string
          )

          write_block_header(io, header)
          io.write(header_data.string)
          io.write(compressed_data)
        end

        # Write terminator block
        #
        # @param io [IO] The output stream
        # @return [void]
        def write_terminator_block(io)
          header = create_block_header(
            type: block_type_code(:terminator),
            flags: 0x4000, # Archive end flag
            data: ""
          )

          write_block_header(io, header)
        end

        # Create a block header
        #
        # @param type [Integer] The block type
        # @param flags [Integer] The block flags
        # @param data [String] The block data
        # @return [Hash] The block header
        def create_block_header(type:, flags:, data:)
          size = 7 + data.bytesize # Header size + data size

          # Calculate header CRC
          temp = StringIO.new
          temp.write([type].pack("C"))
          temp.write([flags].pack("v"))
          temp.write([size].pack("v"))
          temp.write(data) unless data.empty?

          header_crc = calculate_crc32(temp.string) & 0xFFFF

          {
            crc: header_crc,
            type: type,
            flags: flags,
            size: size
          }
        end

        # Write a block header to stream
        #
        # @param io [IO] The output stream
        # @param header [Hash] The header data
        # @return [void]
        def write_block_header(io, header)
          io.write([header[:crc]].pack("v"))
          io.write([header[:type]].pack("C"))
          io.write([header[:flags]].pack("v"))
          io.write([header[:size]].pack("v"))
        end

        # Encode Ruby Time to DOS date/time format
        #
        # @param time [Time] The time to encode
        # @return [Integer] The DOS timestamp
        def encode_dos_time(time)
          second = time.sec / 2
          minute = time.min
          hour = time.hour
          day = time.day
          month = time.month
          year = time.year - 1980

          (year << 25) | (month << 21) | (day << 16) |
            (hour << 11) | (minute << 5) | second
        end
      end
    end
  end
end
