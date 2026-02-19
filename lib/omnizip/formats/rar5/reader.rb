# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require_relative "../rar/rar_format_base"
require_relative "decompressor"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 archive reader
      #
      # Reads RAR 5.x format archives, parsing headers and extracting file data
      # according to the RAR v5 specification.
      #
      # RAR 5 uses variable-length integers (vint) and improved header structure.
      #
      # @example Reading a RAR5 archive
      #   reader = Rar5::Reader.new
      #   File.open("archive.rar", "rb") do |file|
      #     entries = reader.read_archive(file)
      #     entries.each { |entry| puts entry.name }
      #   end
      class Reader < Rar::RarFormatBase
        # Initialize a RAR v5 reader
        def initialize
          super("rar5")
        end

        # Read a RAR v5 archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [FormatError] If the archive format is invalid
        def read_archive(io)
          unless verify_magic_bytes(io)
            raise FormatError, "Invalid RAR v5 signature"
          end

          # Skip past the magic bytes (8 bytes)
          io.seek(8, ::IO::SEEK_SET)

          entries = []

          # Read main header
          main_header = read_header(io)
          unless main_header.type == block_type_code(:main_header)
            raise FormatError, "Expected main archive header"
          end

          @archive_flags = main_header.flags

          # Skip to end of main header
          skip_to_header_end(io, main_header)

          # Read blocks until end marker or EOF/error
          loop do
            header = read_header(io)
            break if header.type == block_type_code(:end_marker)

            case header.type
            when block_type_code(:file_header)
              entry = read_file_entry(io, header)
              entries << entry if entry
            when block_type_code(:service_header)
              skip_header_data(io, header)
            when block_type_code(:encryption_header)
              read_encryption_header(io, header)
            else
              skip_header_data(io, header)
            end
          rescue EOFError, RangeError, FormatError
            # Truncated or corrupted file - return what we have
            break
          end

          entries
        rescue EOFError, RangeError, FormatError
          # Handle truncated/invalid files gracefully
          []
        end

        private

        # Skip to the end of a header
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The header
        def skip_to_header_end(io, header)
          # Calculate end of header: header_start + 4 (CRC) + header_size + vint_length
          header_end = header.header_start + 4 + header.size.to_i + header.vint_length.to_i

          # Validate the offset is reasonable (max 1GB)
          max_offset = 1_073_741_824
          raise RangeError, "Header offset too large" if header_end > max_offset
          raise RangeError, "Header offset negative" if header_end.negative?

          io.seek(header_end, ::IO::SEEK_SET)
        end

        # Read a RAR v5 header
        #
        # @param io [IO] The input stream
        # @return [HeaderBlock] The header block
        def read_header(io)
          # Record start position (before CRC)
          header_start = io.pos

          header_crc = io.read(4)&.unpack1("V")

          # Read header size vint and track its length
          header_size, vint_length = read_vint_with_length(io)

          # Now we're at the start of header content
          # header_size is the size of the content (from header_type to end)
          content_start = io.pos

          header_type = read_vint(io)
          header_flags = read_vint(io)

          # Read extra size if present
          extra_size = 0
          extra_size = read_vint(io) if header_flags & 0x0001 != 0

          # Read data size if present
          data_size = 0
          data_size = read_vint(io) if header_flags & 0x0002 != 0

          # Store positions for proper skipping
          HeaderBlock.new(
            crc: header_crc,
            size: header_size,
            vint_length: vint_length,
            type: header_type,
            flags: header_flags,
            extra_size: extra_size,
            data_size: data_size,
            header_start: header_start,
            content_start: content_start,
          )
        end

        # Read a vint and return both value and length
        #
        # @param io [IO] The input stream
        # @return [Array<Integer, Integer>] Value and length in bytes
        def read_vint_with_length(io)
          result = 0
          shift = 0
          length = 0

          loop do
            byte = io.read(1)&.unpack1("C")
            raise FormatError, "Unexpected EOF" unless byte

            length += 1
            result |= (byte & 0x7F) << shift
            break if byte.nobits?(0x80)

            shift += 7
          end

          [result, length]
        end

        # Read a file entry from archive
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The file header
        # @return [Entry] The file entry
        def read_file_entry(io, header)
          flags = read_vint(io)
          unpacked_size = read_vint(io)
          attributes = read_vint(io)

          # Read modification time if present
          mtime = Time.now
          if flags & 0x02 != 0 # time_present flag
            mtime = read_file_time(io)
          end

          # Read CRC32 if present
          data_crc = 0
          if flags & 0x04 != 0 # crc32_present flag
            data_crc = io.read(4)&.unpack1("V")
          end

          # Read compression info
          compression_flags = read_vint(io)
          host_os = read_vint(io)
          name_length = read_vint(io)

          # Read filename (UTF-8 encoded)
          name_bytes = io.read(name_length)
          filename = name_bytes.force_encoding("UTF-8")

          # Determine if directory
          is_directory = flags.anybits?(0x01) # directory flag

          # Skip to end of header
          skip_to_header_end(io, header)

          # Record data offset before skipping
          data_offset = io.pos

          # Skip file data (so we can read the next header)
          io.seek(header.data_size, ::IO::SEEK_CUR) if header.data_size.to_i.positive?

          Entry.new(
            name: filename,
            compressed_size: header.data_size || 0,
            uncompressed_size: unpacked_size,
            crc32: data_crc,
            compression_method: extract_compression_method(compression_flags),
            modified_time: mtime,
            attributes: attributes,
            encrypted: header.flags.anybits?(0x04),
            data_offset: data_offset,
            host_os: host_os,
            is_directory: is_directory,
          )
        end

        # Extract compression method from flags
        #
        # @param flags [Integer] The compression flags
        # @return [Symbol] The compression method
        def extract_compression_method(flags)
          method_code = flags & 0x07

          case method_code
          when 0 then :store
          when 1 then :fastest
          when 2 then :fast
          when 3 then :normal
          when 4 then :good
          when 5 then :best
          else :normal
          end
        end

        # Read file time in RAR5 format
        #
        # @param io [IO] The input stream
        # @return [Time] The file time
        def read_file_time(io)
          read_vint(io)

          # Simplified time reading - actual format is more complex
          unix_time = io.read(8)&.unpack1("Q<")
          Time.at(unix_time / 10_000_000.0) if unix_time
        rescue ArgumentError
          Time.now
        end

        # Read encryption header
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The header
        # @return [void]
        def read_encryption_header(io, header)
          # Read and skip encryption data
          skip_header_data(io, header)
        end

        # Skip header data
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The header
        # @return [void]
        def skip_header_data(io, header)
          # Calculate end of header: header_start + 4 (CRC) + header_size + vint_length
          header_end = header.header_start.to_i + 4 + header.size.to_i + header.vint_length.to_i
          current_pos = io.pos

          # Validate the offset is reasonable (max 1GB)
          max_offset = 1_073_741_824
          if header_end > max_offset || header_end.negative?
            raise RangeError, "Invalid header offset"
          end

          if header_end > current_pos
            io.seek(header_end - current_pos, ::IO::SEEK_CUR)
          end

          # Skip data section if present (with bounds checking)
          data_size = header.data_size.to_i
          if data_size.positive? && data_size < max_offset
            io.seek(data_size, ::IO::SEEK_CUR)
          end
        end
      end

      # RAR v5 header block model
      class HeaderBlock
        attr_accessor :crc, :size, :vint_length, :type, :flags, :extra_size,
                      :data_size, :header_start, :content_start

        def initialize(crc: nil, size: nil, vint_length: 1, type: nil, flags: nil,
                       extra_size: nil, data_size: nil, header_start: nil, content_start: nil)
          @crc = crc
          @size = size
          @vint_length = vint_length
          @type = type
          @flags = flags
          @extra_size = extra_size
          @data_size = data_size
          @header_start = header_start
          @content_start = content_start
        end
      end

      # RAR v5 archive entry model
      class Entry
        attr_accessor :name, :compressed_size, :uncompressed_size, :crc32,
                      :compression_method, :modified_time, :attributes,
                      :encrypted, :data_offset, :host_os, :is_directory

        def initialize(name: nil, compressed_size: nil, uncompressed_size: nil,
                       crc32: nil, compression_method: nil, modified_time: nil,
                       attributes: nil, encrypted: nil, data_offset: nil,
                       host_os: nil, is_directory: nil)
          @name = name
          @compressed_size = compressed_size
          @uncompressed_size = uncompressed_size
          @crc32 = crc32
          @compression_method = compression_method
          @modified_time = modified_time
          @attributes = attributes
          @encrypted = encrypted
          @data_offset = data_offset
          @host_os = host_os
          @is_directory = is_directory
        end
      end
    end
  end
end
