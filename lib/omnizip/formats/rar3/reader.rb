# frozen_string_literal: true

require "lutaml/model"
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
          io.pos

          # Read marker block
          marker = read_block_header(io)
          unless marker.type == block_type_code(:marker)
            raise FormatError, "Expected marker block"
          end

          # Read archive header
          archive_header = read_block_header(io)
          unless archive_header.type == block_type_code(:archive)
            raise FormatError, "Expected archive header"
          end

          @archive_flags = archive_header.flags

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
        end

        private

        # Read a block header
        #
        # @param io [IO] The input stream
        # @return [BlockHeader] The block header
        def read_block_header(io)
          header_crc = io.read(2)&.unpack1("v")
          type = io.read(1)&.unpack1("C")
          flags = io.read(2)&.unpack1("v")
          size = io.read(2)&.unpack1("v")

          raise FormatError, "Unexpected EOF" unless size

          # Check if header has additional size field
          if flags & 0x8000 != 0
            add_size = io.read(4)&.unpack1("V")
            size += add_size
          end

          BlockHeader.new(
            crc: header_crc,
            type: type,
            flags: flags,
            size: size,
            position: io.pos
          )
        end

        # Read a file entry from archive
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The file block header
        # @return [Entry] The file entry
        def read_file_entry(io, block)
          packed_size = io.read(4)&.unpack1("V")
          unpacked_size = io.read(4)&.unpack1("V")
          host_os = io.read(1)&.unpack1("C")
          file_crc = io.read(4)&.unpack1("V")
          file_time = io.read(4)&.unpack1("V")
          io.read(1)&.unpack1("C")
          method = io.read(1)&.unpack1("C")
          name_size = io.read(2)&.unpack1("v")
          attr = io.read(4)&.unpack1("V")

          # Read filename
          name_bytes = io.read(name_size)
          filename = decode_filename(name_bytes, block.flags)

          # Handle large file sizes
          if block.flags & spec.format.file_flags[:large_file] != 0
            high_packed = io.read(4)&.unpack1("V")
            high_unpacked = io.read(4)&.unpack1("V")
            packed_size |= (high_packed << 32)
            unpacked_size |= (high_unpacked << 32)
          end

          # Read salt if encrypted
          salt = nil
          salt = io.read(8) if block.flags & spec.format.file_flags[:salt] != 0

          # Read extended time if present
          mtime = parse_dos_time(file_time)
          if block.flags & spec.format.file_flags[:ext_time] != 0
            mtime = read_extended_time(io)
          end

          # Skip to compressed data
          header_size = io.pos - block.position
          data_offset = block.position + header_size

          Entry.new(
            name: filename,
            compressed_size: packed_size,
            uncompressed_size: unpacked_size,
            crc32: file_crc,
            compression_method: compression_method_name(method),
            modified_time: mtime,
            attributes: attr,
            encrypted: block.flags.anybits?(spec.format.file_flags[:encrypted]),
            data_offset: data_offset,
            host_os: host_os,
            salt: salt
          )
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
          data_size = block.size - (io.pos - block.position)
          comment = io.read(data_size)
          comment&.force_encoding("UTF-8")
        end

        # Skip block data
        #
        # @param io [IO] The input stream
        # @param block [BlockHeader] The block header
        # @return [void]
        def skip_block_data(io, block)
          remaining = block.size - (io.pos - block.position)
          io.seek(remaining, IO::SEEK_CUR) if remaining.positive?
        end
      end

      # RAR v3 block header model
      class BlockHeader < Lutaml::Model::Serializable
        attribute :crc, :integer
        attribute :type, :integer
        attribute :flags, :integer
        attribute :size, :integer
        attribute :position, :integer
      end

      # RAR archive entry model
      class Entry < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :compressed_size, :integer
        attribute :uncompressed_size, :integer
        attribute :crc32, :integer
        attribute :compression_method, :string
        attribute :modified_time, :string
        attribute :attributes, :integer
        attribute :encrypted, :boolean
        attribute :data_offset, :integer
        attribute :host_os, :integer
        attribute :salt, :string
      end
    end
  end
end
