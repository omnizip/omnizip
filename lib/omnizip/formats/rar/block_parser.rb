# frozen_string_literal: true

require_relative "constants"
require_relative "models/rar_entry"

module Omnizip
  module Formats
    module Rar
      # RAR block parser
      # Parses different block types in RAR archives
      class BlockParser
        include Constants

        attr_reader :version

        # Initialize block parser
        #
        # @param version [Integer] RAR version (4 or 5)
        def initialize(version)
          @version = version
        end

        # Parse file block and create entry
        #
        # @param io [IO] Input stream
        # @return [Models::RarEntry, nil] Parsed entry or nil
        def parse_file_block(io)
          if @version == 5
            parse_rar5_file_block(io)
          else
            parse_rar4_file_block(io)
          end
        end

        # Skip to next block
        #
        # @param io [IO] Input stream
        # @param block_size [Integer] Block size to skip
        def skip_block(io, block_size)
          io.read(block_size) if block_size.positive?
        end

        private

        # Parse RAR4 file block
        #
        # @param io [IO] Input stream
        # @return [Models::RarEntry, nil] Parsed entry or nil
        def parse_rar4_file_block(io)
          entry = Models::RarEntry.new

          # Read block header
          read_uint16(io)
          head_type = io.read(1)&.ord
          return nil unless head_type == BLOCK_FILE

          head_flags = read_uint16(io)
          head_size = read_uint16(io)

          # Read file header data
          pack_size = read_uint32(io)
          unpack_size = read_uint32(io)
          host_os = io.read(1)&.ord
          file_crc = read_uint32(io)
          file_time = read_uint32(io)
          unpack_ver = io.read(1)&.ord
          method = io.read(1)&.ord
          name_size = read_uint16(io)
          attr = read_uint32(io)

          # Read extended sizes if large file
          if head_flags.anybits?(FILE_LARGE)
            high_pack_size = read_uint32(io)
            high_unpack_size = read_uint32(io)
            pack_size |= (high_pack_size << 32)
            unpack_size |= (high_unpack_size << 32)
          end

          # Read file name
          name_bytes = io.read(name_size)
          entry.name = decode_filename(name_bytes, head_flags)

          # Set entry properties
          entry.size = unpack_size
          entry.compressed_size = pack_size
          entry.crc = file_crc
          entry.host_os = host_os
          entry.method = method
          entry.version = unpack_ver
          entry.flags = head_flags
          entry.attributes = attr
          entry.mtime = dos_time_to_time(file_time)

          # Set flags
          entry.is_dir = head_flags.anybits?(FILE_DIRECTORY)
          entry.encrypted = head_flags.anybits?(FILE_ENCRYPTED)
          entry.split_before = head_flags.anybits?(FILE_SPLIT_BEFORE)
          entry.split_after = head_flags.anybits?(FILE_SPLIT_AFTER)

          # Skip remaining header data and file data
          remaining = head_size - (name_size + 25)
          remaining += 8 if head_flags.anybits?(FILE_LARGE)
          io.read(remaining) if remaining.positive?
          io.read(pack_size) # Skip compressed data

          entry
        end

        # Parse RAR5 file block
        #
        # @param io [IO] Input stream
        # @return [Models::RarEntry, nil] Parsed entry or nil
        def parse_rar5_file_block(io)
          entry = Models::RarEntry.new

          # Read block header
          read_uint32(io)
          read_vint(io)
          header_type = read_vint(io)
          return nil unless header_type == RAR5_HEADER_FILE

          header_flags = read_vint(io)

          # Read file header
          file_flags = read_vint(io)
          unpack_size = read_vint(io)
          attr = read_vint(io)

          # Read modification time if present
          mtime = nil
          mtime = read_uint32(io) if file_flags.anybits?(0x02)

          # Read CRC if present
          crc = nil
          crc = read_uint32(io) if file_flags.anybits?(0x04)

          # Read compression info
          read_vint(io)
          host_os = read_vint(io)
          name_length = read_vint(io)

          # Read file name
          name_bytes = io.read(name_length)
          entry.name = name_bytes.force_encoding("UTF-8")

          # Set entry properties
          entry.size = unpack_size
          entry.compressed_size = 0 # Not directly available in header
          entry.crc = crc
          entry.host_os = host_os
          entry.flags = file_flags
          entry.attributes = attr
          entry.mtime = Time.at(mtime) if mtime
          entry.is_dir = file_flags.anybits?(RAR5_FLAG_IS_DIR)
          entry.version = 5

          # Read extra area if present
          if header_flags.anybits?(RAR5_FLAG_EXTRA_AREA)
            extra_size = read_vint(io)
            io.read(extra_size) if extra_size.positive?
          end

          # Read data area if present
          if header_flags.anybits?(RAR5_FLAG_DATA_AREA)
            data_size = read_vint(io)
            io.read(data_size) if data_size.positive?
          end

          entry
        end

        # Decode filename from bytes
        #
        # @param bytes [String] Raw filename bytes
        # @param flags [Integer] Block flags
        # @return [String] Decoded filename
        def decode_filename(bytes, flags)
          if flags.nobits?(FILE_UNICODE)
            # ASCII filename
            bytes.force_encoding("ASCII-8BIT")
          else
            # Unicode filename
            bytes.force_encoding("UTF-8")
          end
        end

        # Convert DOS time to Ruby Time
        #
        # @param dos_time [Integer] DOS time value
        # @return [Time] Ruby time object
        def dos_time_to_time(dos_time)
          sec = (dos_time & 0x1F) * 2
          min = (dos_time >> 5) & 0x3F
          hour = (dos_time >> 11) & 0x1F
          day = (dos_time >> 16) & 0x1F
          month = (dos_time >> 21) & 0x0F
          year = ((dos_time >> 25) & 0x7F) + 1980

          Time.new(year, month, day, hour, min, sec)
        rescue ArgumentError
          Time.now
        end

        # Read 16-bit unsigned integer (little-endian)
        def read_uint16(io)
          bytes = io.read(2)
          return 0 unless bytes&.size == 2

          bytes.unpack1("v")
        end

        # Read 32-bit unsigned integer (little-endian)
        def read_uint32(io)
          bytes = io.read(4)
          return 0 unless bytes&.size == 4

          bytes.unpack1("V")
        end

        # Read variable-length integer (RAR5)
        def read_vint(io)
          result = 0
          shift = 0

          loop do
            byte = io.read(1)&.ord
            return result unless byte

            result |= (byte & 0x7F) << shift
            break if byte.nobits?(0x80)

            shift += 7
          end

          result
        end
      end
    end
  end
end
