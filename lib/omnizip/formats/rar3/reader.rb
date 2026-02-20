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
    module Rar3
      # RAR v3 archive reader
      #
      # Reads RAR 3.x format archives, parsing headers and extracting file data
      # according to the RAR v3 specification.
      #
      # @example Reading a RAR3 archive
      #   reader = Rar3::Reader.new
      #   File.open("archive.rar", "rb") do |file|
      #     entries = reader.read_archive(file)
      #     entries.each { |entry| puts entry.name }
      #   end
      class Reader < Rar::RarFormatBase
        # Initialize a RAR v3 reader
        def initialize
          super("rar3")
        end

        # Read a RAR v3 archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [FormatError] If the archive format is invalid
        def read_archive(io)
          unless verify_magic_bytes(io)
            raise FormatError, "Invalid RAR v3 signature"
          end

          entries = []

          # RAR4 marker is the signature itself (7 bytes): "Rar!\x1a\x07\x00"
          # Skip past the marker to read the archive header
          io.seek(7, ::IO::SEEK_SET)

          # Read first block - could be archive header or file block (for minimal archives)
          first_block = read_block_header(io)

          if first_block.type == block_type_code(:archive)
            # Standard archive with archive header
            @archive_flags = first_block.flags

            # Skip past archive header block (header + data)
            # SIZE field contains total block size
            block_end = first_block.header_start + first_block.size
            io.seek(block_end, ::IO::SEEK_SET)
          elsif first_block.type == block_type_code(:file)
            # Minimal archive without archive header - process as file block
            entry = read_file_entry(io, first_block)
            entries << entry if entry
          else
            raise FormatError,
                  "Expected archive header or file header, got type #{first_block.type}"
          end

          # Read file blocks until end
          loop do
            block = read_block_header(io)
            break if block.type == block_type_code(:terminator)

            case block.type
            when block_type_code(:file)
              entry = read_file_entry(io, block)
              entries << entry if entry
            when block_type_code(:comment)
              read_comment_block(io, block)
            when block_type_code(:recovery)
              skip_block_data(io, block)
            else
              skip_block_data(io, block)
            end
          end

          entries
        rescue EOFError, FormatError
          # Handle truncated or malformed files gracefully
          entries
        end

        private

        # Read a block header
        #
        # @param io [IO] The input stream
        # @return [BlockHeader] The block header
        def read_block_header(io)
          # Record position BEFORE reading header
          header_start = io.pos

          header_crc = io.read(2)&.unpack1("v")
          type = io.read(1)&.unpack1("C")
          flags = io.read(2)&.unpack1("v")
          size = io.read(2)&.unpack1("v")

          raise FormatError, "Unexpected EOF" unless size

          # For FILE blocks, the SIZE field directly contains the total header size
          # The file_header structure starts immediately after the 7-byte block header
          # No additional 4-byte field needed for FILE blocks
          header_size = 7 # CRC(2) + TYPE(1) + FLAGS(2) + SIZE(2)

          BlockHeader.new(
            crc: header_crc,
            type: type,
            flags: flags,
            size: size,
            header_start: header_start,
            header_size: header_size,
          )
        end

        # Skip to the data portion of a block (after header)
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The block header
        def skip_to_block_data(io, block)
          target_pos = block.header_start + block.header_size
          current_pos = io.pos
          if target_pos > current_pos
            io.seek(target_pos, ::IO::SEEK_SET)
          end
        end

        # Read a file entry from archive
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The file block header
        # @return [Entry] The file entry
        def read_file_entry(io, block)
          # The SIZE field contains the total size of the block header (including data after 7-byte prefix)
          # The data portion after the 7-byte block header is: size - 7 bytes
          block.header_start + 7 # Start of header data after 7-byte prefix
          header_data_size = block.size - 7

          # Read all header data at once
          header_data = io.read(header_data_size)
          unless header_data
            raise FormatError,
                  "Unexpected EOF reading file header"
          end

          # Now parse the file_header from the start of header_data
          pos = 0

          packed_size = header_data[pos, 4].unpack1("V")
          pos += 4

          unpacked_size = header_data[pos, 4].unpack1("V")
          pos += 4

          host_os = header_data[pos, 1].unpack1("C")
          pos += 1

          file_crc = header_data[pos, 4].unpack1("V")
          pos += 4

          file_time = header_data[pos, 4].unpack1("V")
          pos += 4

          header_data[pos, 1].unpack1("C")
          pos += 1

          method = header_data[pos, 1].unpack1("C")
          pos += 1

          name_size = header_data[pos, 2].unpack1("v")
          pos += 2

          attr = header_data[pos, 4].unpack1("V")
          pos += 4

          # Read filename
          name_bytes = header_data[pos, name_size]
          pos += name_size
          filename = decode_filename(name_bytes, block.flags)

          # Handle large file sizes
          if block.flags & 0x0100 != 0 # large_file flag
            high_packed = header_data[pos, 4].unpack1("V")
            high_unpacked = header_data[pos + 4, 4].unpack1("V")
            packed_size |= (high_packed << 32)
            unpacked_size |= (high_unpacked << 32)
            pos += 8
          end

          # Read salt if encrypted
          salt = nil
          if block.flags & 0x0400 != 0 # salt flag
            salt = header_data[pos, 8]
            pos += 8
          end

          # Read extended time if present
          mtime = parse_dos_time(file_time)
          if block.flags & 0x1000 != 0 # ext_time flag
            # Extended time format: mtime[4] + ctime[4] + atime[4] + arctime[4] + flags
            # Plus additional 3 bytes for each present time
            mtime, = read_extended_time_data(header_data, pos)
          end

          # We've already read all header data, no need to seek
          # Just skip to end of block and then past file data

          # Record data offset (start of file data)
          data_offset = block.header_start + block.size

          # Current position should be at end of header data
          # Skip past file data to prepare for next block
          # Use read instead of seek for better compatibility with non-seekable streams
          if packed_size.positive?
            begin
              io.seek(packed_size, ::IO::SEEK_CUR)
            rescue Errno::EINVAL, Errno::ESPIPE
              # Stream doesn't support seeking - read and discard instead
              remaining = packed_size
              while remaining.positive?
                chunk = io.read([remaining, 8192].min)
                break unless chunk

                remaining -= chunk.bytesize
              end
            end
          end

          Entry.new(
            name: filename,
            compressed_size: packed_size,
            uncompressed_size: unpacked_size,
            crc32: file_crc,
            compression_method: compression_method_name(method),
            modified_time: mtime,
            attributes: attr,
            encrypted: block.flags.anybits?(0x0004), # encrypted flag
            data_offset: data_offset,
            host_os: host_os,
            salt: salt,
          )
        end

        # Read extended time from header data
        #
        # @param data [String] The header data
        # @param pos [Integer] Current position in data
        # @return [Array<Time, Integer>] The modification time and new position
        def read_extended_time_data(data, pos)
          return [Time.now, pos] if pos + 4 > data.bytesize

          mtime = parse_dos_time(data[pos, 4].unpack1("V"))
          pos += 4

          # Skip ctime, atime, arctime if present
          begin
            data[pos, 1].unpack1("C")
          rescue StandardError
            0
          end
          pos += 1

          # For now, just skip the remaining extended time data
          # The format is complex and varies

          [mtime, pos]
        rescue ArgumentError
          [Time.now, pos]
        end

        # Decode filename based on encoding flags
        #
        # @param bytes [String] The filename bytes
        # @param flags [Integer] The file flags
        # @return [String] The decoded filename
        def decode_filename(bytes, flags)
          if flags.nobits?(spec.format.file_flags[:unicode])
            # Legacy encoding - assume CP437 or system encoding
            bytes.force_encoding("CP437").encode("UTF-8", invalid: :replace)
          else
            # Unicode filename - decode UTF-8
            bytes.force_encoding("UTF-8")
          end
        end

        # Parse DOS date/time to Ruby Time
        #
        # @param dos_time [Integer] The DOS timestamp
        # @return [Time] The parsed time
        def parse_dos_time(dos_time)
          second = (dos_time & 0x1F) * 2
          minute = (dos_time >> 5) & 0x3F
          hour = (dos_time >> 11) & 0x1F
          day = (dos_time >> 16) & 0x1F
          month = (dos_time >> 21) & 0x0F
          year = ((dos_time >> 25) & 0x7F) + 1980

          Time.new(year, month, day, hour, minute, second)
        rescue ArgumentError
          Time.now
        end

        # Read extended time information
        #
        # @param io [IO] The input stream
        # @return [Time] The extended time
        def read_extended_time(io)
          io.read(2)&.unpack1("v")
          # Extended time format varies, simplified implementation
          Time.now
        end

        # Read comment block
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The block header
        # @return [String] The comment text
        def read_comment_block(io, block)
          current_pos = io.pos
          header_end = block.header_start + block.header_size
          data_size = block.size - block.header_size
          remaining = data_size - (current_pos - header_end)
          comment = io.read(remaining) if remaining.positive?
          comment&.force_encoding("UTF-8")
        end

        # Skip block data
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The block header
        # @return [void]
        def skip_block_data(io, block)
          # block.size is the total size, calculate remaining bytes
          current_pos = io.pos
          header_end = block.header_start + block.header_size
          data_size = block.size - block.header_size
          remaining = data_size - (current_pos - header_end)
          io.seek(remaining, ::IO::SEEK_CUR) if remaining.positive?
        end
      end

      # RAR v3 block header model
      class BlockHeader
        attr_accessor :crc, :type, :flags, :size, :header_start, :header_size

        def initialize(crc: nil, type: nil, flags: nil, size: nil,
                       header_start: nil, header_size: 7)
          @crc = crc
          @type = type
          @flags = flags
          @size = size
          @header_start = header_start
          @header_size = header_size
        end
      end

      # RAR archive entry model
      class Entry
        attr_accessor :name, :compressed_size, :uncompressed_size, :crc32,
                      :compression_method, :modified_time, :attributes,
                      :encrypted, :data_offset, :host_os, :salt

        def initialize(name: nil, compressed_size: nil, uncompressed_size: nil,
                       crc32: nil, compression_method: nil, modified_time: nil,
                       attributes: nil, encrypted: nil, data_offset: nil,
                       host_os: nil, salt: nil)
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
          @salt = salt
        end
      end
    end
  end
end
