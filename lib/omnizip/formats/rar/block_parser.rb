# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # RAR block parser
      # Parses different block types in RAR archives
      class BlockParser
        include Omnizip::Formats::Rar::Constants

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
          block_start = io.pos

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

          # Sanity bounds: corrupt headers must not drive huge reads.
          # head_size can never exceed the bytes left from the block
          # start, and the name must fit inside the header.
          if head_size > io.size - block_start ||
              name_size + 32 > head_size
            return nil
          end

          # Read file name
          name_bytes = io.read(name_size)
          entry.name = decode_filename(name_bytes, head_flags)
          # RAR4 archives store DOS-style backslash separators;
          # normalize to forward slashes like unrar on Unix. Scrub
          # first: unicode-flagged names may carry bytes that are not
          # valid UTF-8, and String#tr raises on them under any
          # locale.
          entry.name = entry.name.scrub.tr("\\", "/")

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

          # Set flags. RAR4 directory entries carry the full
          # dictionary mask 0xE0 in HEAD_FLAGS (a directory has no
          # dictionary); the exact match avoids misreading a large
          # dictionary size on files as the marker.
          entry.is_dir = head_flags.allbits?(FILE_DIRECTORY)
          # WinRAR writes directory names with a trailing backslash;
          # normalize it away for host paths.
          entry.name = entry.name.chomp("\\") if entry.is_dir
          entry.encrypted = head_flags.anybits?(FILE_ENCRYPTED)
          entry.split_before = head_flags.anybits?(FILE_SPLIT_BEFORE)
          entry.split_after = head_flags.anybits?(FILE_SPLIT_AFTER)

          # Skip remaining header data and file data. HEAD_SIZE
          # counts the whole block including the 2-byte HEAD_CRC;
          # consumed so far: 2 (CRC) + 30 (fixed fields) + name, plus
          # 8 more when high-size words were present. Leftover bytes
          # cover salt/extra time fields without interpreting them.
          remaining = head_size - (name_size + 32)
          remaining -= 8 if head_flags.anybits?(FILE_LARGE)
          io.read(remaining) if remaining.positive?
          # Record where the packed data starts so extraction can seek
          # straight to it instead of re-parsing the archive
          entry.data_offset = io.pos
          # Seek past the data: never allocate the packed bytes just
          # to skip them (a corrupt pack_size must not request
          # gigabytes of memory)
          io.seek(pack_size, ::IO::SEEK_CUR)

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

          # Optional ExtraAreaSize / DataSize precede the file fields
          extra_size = header_flags.anybits?(RAR5_FLAG_EXTRA_AREA) ? read_vint(io) : 0
          data_size = header_flags.anybits?(RAR5_FLAG_DATA_AREA) ? read_vint(io) : 0

          # Sanity bounds: corrupt headers must not drive huge reads
          remaining_bytes = io.size - io.pos
          return nil if extra_size > remaining_bytes || data_size > remaining_bytes

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
          entry.name = name_bytes.to_s.scrub.force_encoding("UTF-8")

          # Set entry properties
          entry.size = unpack_size
          entry.compressed_size = data_size
          entry.crc = crc
          entry.host_os = host_os
          entry.flags = file_flags
          entry.attributes = attr
          entry.mtime = Time.at(mtime) if mtime
          entry.is_dir = file_flags.anybits?(RAR5_FLAG_IS_DIR)
          entry.version = 5

          # Skip extra area, then compressed data; record the data
          # start for direct-seek extraction. The data is seeked past,
          # never read: corrupt sizes must not drive huge allocations.
          io.read(extra_size) if extra_size.positive?
          entry.data_offset = io.pos
          io.seek(data_size, ::IO::SEEK_CUR)

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
