# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require "stringio"
require_relative "../rar/rar_format_base"
require_relative "compressor"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 archive writer
      #
      # Writes RAR 5.x format archives, creating headers and compressing file
      # data according to the RAR v5 specification.
      #
      # RAR 5 uses variable-length integers and improved header structure.
      #
      # @example Writing a RAR5 archive
      #   writer = Rar5::Writer.new
      #   File.open("archive.rar", "wb") do |file|
      #     entries = [
      #       {name: "file.txt", data: "content", time: Time.now}
      #     ]
      #     writer.write_archive(file, entries)
      #   end
      class Writer < Rar::RarFormatBase
        # Initialize a RAR v5 writer
        def initialize
          super("rar5")
          @compressor = Compressor.new
        end

        # Write a RAR v5 archive
        #
        # @param io [IO] The output stream
        # @param entries [Array<Hash>] The entries to write
        # @return [void]
        def write_archive(io, entries)
          # Write magic bytes
          io.write(spec.magic_bytes.pack("C*"))

          # Write main header
          write_main_header(io)

          # Write file entries
          entries.each do |entry|
            write_file_entry(io, entry)
          end

          # Write end marker
          write_end_marker(io)
        end

        private

        # Write main archive header
        #
        # @param io [IO] The output stream
        # @return [void]
        def write_main_header(io)
          flags = 0

          header_data = StringIO.new
          write_vint(header_data, flags)

          write_header(
            io,
            type: block_type_code(:main_header),
            flags: 0,
            data: header_data.string,
          )
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
          compressed_data.bytesize
          unpacked_size = data.bytesize
          file_crc = calculate_crc32(data)

          # Encode filename to UTF-8
          name_bytes = name.encode("UTF-8")
          name_length = name_bytes.bytesize

          # Build file header data
          file_flags = spec.format.file_header_flags[:time_present] |
            spec.format.file_header_flags[:crc32_present]

          compression_info = compression_method_code(method) & 0x07

          header_data = StringIO.new
          write_vint(header_data, file_flags)
          write_vint(header_data, unpacked_size)
          write_vint(header_data, 0x20) # Attributes (normal file)

          # Write modification time
          write_file_time(header_data, mtime)

          # Write CRC32
          header_data.write([file_crc].pack("V"))

          # Write compression info
          write_vint(header_data, compression_info)
          write_vint(header_data, spec.format.host_os[:windows])
          write_vint(header_data, name_length)
          header_data.write(name_bytes)

          # Write header with data
          write_header(
            io,
            type: block_type_code(:file_header),
            flags: 0x0002, # Has data size
            data: header_data.string,
            data_section: compressed_data,
          )
        end

        # Write end marker
        #
        # @param io [IO] The output stream
        # @return [void]
        def write_end_marker(io)
          write_header(
            io,
            type: block_type_code(:end_marker),
            flags: 0x0004, # Archive end flag
            data: "",
          )
        end

        # Write a RAR v5 header
        #
        # @param io [IO] The output stream
        # @param type [Integer] The header type
        # @param flags [Integer] The header flags
        # @param data [String] The header data
        # @param data_section [String, nil] Optional data section
        # @return [void]
        def write_header(io, type:, flags:, data:, data_section: nil)
          header_io = StringIO.new

          # Calculate header size (not including CRC)
          size_bytes = StringIO.new
          write_vint(size_bytes, type)
          write_vint(size_bytes, flags)

          if data_section
            flags |= 0x0002 # Has data size flag
            write_vint(size_bytes, data_section.bytesize)
          end

          size_bytes.write(data)

          header_size = size_bytes.string.bytesize

          # Write size vint
          write_vint(header_io, header_size)

          # Write type and flags
          write_vint(header_io, type)
          write_vint(header_io, flags)

          # Write data size if present
          write_vint(header_io, data_section.bytesize) if data_section

          # Write header data
          header_io.write(data)

          # Calculate CRC32 of header (excluding CRC field itself)
          header_crc = calculate_crc32(header_io.string)

          # Write CRC and header to output
          io.write([header_crc].pack("V"))
          io.write(header_io.string)

          # Write data section if present
          io.write(data_section) if data_section
        end

        # Write file time in RAR5 format
        #
        # @param io [IO] The output stream
        # @param time [Time] The time to write
        # @return [void]
        def write_file_time(io, time)
          # RAR5 uses Windows FILETIME format (100-nanosecond intervals since
          # 1601-01-01). Simplified implementation.
          unix_time = time.to_i
          windows_time = (unix_time + 11_644_473_600) * 10_000_000

          write_vint(io, 0x01) # Time flags (modification time present)
          io.write([windows_time].pack("Q<"))
        end
      end
    end
  end
end
