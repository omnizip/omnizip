# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        # Header types
        HEADER_TYPE_MAIN = 1
        HEADER_TYPE_FILE = 2
        HEADER_TYPE_SERVICE = 3
        HEADER_TYPE_ENCRYPTION = 4
        HEADER_TYPE_END = 5

        # Header flags (common)
        FLAG_EXTRA_AREA = 0x0001
        FLAG_DATA_AREA = 0x0002

        # Base class for RAR5 headers
        class Header
          attr_reader :type, :flags, :extra_area, :data_area_size, :header_data

          def initialize(type, flags: 0, extra_area: nil, data_area_size: nil,
header_data: "")
            @type = type
            @flags = flags
            @flags |= FLAG_EXTRA_AREA if extra_area
            @flags |= FLAG_DATA_AREA if data_area_size
            @extra_area = extra_area
            @data_area_size = data_area_size
            @header_data = header_data
          end

          def encode
            # Build header without CRC
            header_bytes = build_header_bytes

            # Calculate CRC32
            crc = CRC32.calculate(header_bytes.pack("C*"))

            # Prepend CRC (little-endian)
            [crc].pack("V") + header_bytes.pack("C*")
          end

          private

          def build_header_bytes
            bytes = []

            # Header size (placeholder - will calculate)
            size_bytes = []

            # Type
            type_bytes = VINT.encode(@type)
            size_bytes.concat(type_bytes)

            # Flags
            flags_bytes = VINT.encode(@flags)
            size_bytes.concat(flags_bytes)

            # Extra area size (if present)
            if @flags.anybits?(FLAG_EXTRA_AREA)
              extra_size_bytes = VINT.encode(@extra_area.bytesize)
              size_bytes.concat(extra_size_bytes)
            end

            # Data area size (if present)
            if @flags.anybits?(FLAG_DATA_AREA)
              data_size_bytes = VINT.encode(@data_area_size)
              size_bytes.concat(data_size_bytes)
            end

            # Header data
            size_bytes.concat(@header_data.bytes)

            # Extra area
            size_bytes.concat(@extra_area.bytes) if @extra_area

            # Calculate total header size (excluding CRC)
            header_size = size_bytes.size
            header_size_vint = VINT.encode(header_size)

            # Build final header
            bytes.concat(header_size_vint)
            bytes.concat(size_bytes)

            bytes
          end
        end

        # Main archive header
        class MainHeader < Header
          # Archive flags: 0x0001 volume, 0x0002 volume number
          # present, 0x0004 solid, 0x0008 recovery, 0x0010 locked
          ARCHIVE_FLAG_VOLUME = 0x0001
          ARCHIVE_FLAG_VOLUME_NUMBER = 0x0002

          def initialize(archive_flags: 0, volume_number: nil)
            data = VINT.encode(archive_flags)
            if archive_flags.anybits?(ARCHIVE_FLAG_VOLUME_NUMBER)
              data.concat(VINT.encode(volume_number.to_i))
            end

            super(HEADER_TYPE_MAIN, header_data: data.pack("C*"))
          end
        end

        # File header
        class FileHeader < Header
          # File header flags
          FILE_HAS_ATTRIBUTES = 0x0001
          FILE_HAS_MTIME = 0x0002
          FILE_HAS_CRC32 = 0x0004

          # Compression information field layout (RAR 5.0 spec):
          # bits 0-5 algorithm version (0), bit 7 solid,
          # bits 8-10 method (0=store, 1-5=LZMA), bits 11-15
          # dictionary size (128 KB * 2^N).
          DICT_BASE = 128 * 1024

          def initialize(filename:, file_size:, compressed_size:,
                         compression_method: 0, dict_size: 0,
                         flags: 0, mtime: nil, crc32: nil, extra_area: nil)
            # Build file flags based on what's provided
            file_flags = 0
            file_flags |= FILE_HAS_MTIME if mtime
            file_flags |= FILE_HAS_CRC32 if crc32

            # Build header data with file information
            data = build_file_data(filename, file_size,
                                   compression_method, dict_size,
                                   file_flags, mtime, crc32)
            super(HEADER_TYPE_FILE, flags: flags, data_area_size: compressed_size, header_data: data, extra_area: extra_area)
          end

          private

          def build_file_data(filename, file_size, compression_method,
                              dict_size, file_flags, mtime, crc32)
            data = []

            # File flags (VINT)
            data.concat(VINT.encode(file_flags))

            # Unpacked size (VINT)
            data.concat(VINT.encode(file_size))

            # Attributes (VINT) - ALWAYS present in RAR5.
            # Unix host: standard regular-file mode 0o100644.
            data.concat(VINT.encode(0o100644))

            # mtime (optional) - only if FILE_HAS_MTIME flag is set
            # RAR5 stores mtime as Unix timestamp (seconds since epoch)
            # Format: 4 bytes little-endian (NOT a VINT)
            if file_flags.anybits?(FILE_HAS_MTIME) && mtime
              data.concat([mtime.to_i].pack("V").bytes)
            end

            # Data CRC32 (optional) - only if FILE_HAS_CRC32 flag is set
            # Format: 4 bytes little-endian (NOT a VINT)
            if file_flags.anybits?(FILE_HAS_CRC32) && crc32
              data.concat([crc32].pack("V").bytes)
            end

            # Compression information (VINT): version 0 in bits 0-5,
            # method in bits 8-10, dictionary size in bits 11-15
            # (128 KB * 2^N).
            dict_bits = if dict_size.positive?
                          Math.log2(dict_size / DICT_BASE).round.clamp(0, 15)
                        else
                          0
                        end
            compression_info = (compression_method << 8) | (dict_bits << 11)
            data.concat(VINT.encode(compression_info))

            # Host OS (VINT) - 1 = Unix
            data.concat(VINT.encode(1))

            # Name length (VINT) and name
            name_bytes = filename.encode("UTF-8").bytes
            data.concat(VINT.encode(name_bytes.size))
            data.concat(name_bytes)

            data.pack("C*")
          end
        end

        # End of archive header
        class EndHeader < Header
          # End of archive flags: 0x0001 volume and not the last
          # volume in the set
          END_FLAG_VOLUME_NEXT = 0x0001

          def initialize(end_flags: 0)
            super(HEADER_TYPE_END,
                  header_data: VINT.encode(end_flags).pack("C*"))
          end
        end
      end
    end
  end
end
