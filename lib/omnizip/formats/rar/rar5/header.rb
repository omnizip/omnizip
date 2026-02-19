# frozen_string_literal: true

require_relative "vint"
require_relative "crc32"

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
          def initialize(flags: 0)
            # Main header has no data
            super(HEADER_TYPE_MAIN, flags: flags)
          end
        end

        # File header
        class FileHeader < Header
          # File header flags
          FILE_HAS_ATTRIBUTES = 0x0001
          FILE_HAS_MTIME = 0x0002
          FILE_HAS_CRC32 = 0x0004

          def initialize(filename:, file_size:, compressed_size:,
compression_method: 0, flags: 0, mtime: nil, crc32: nil, extra_area: nil)
            # Build file flags based on what's provided
            file_flags = 0
            file_flags |= FILE_HAS_MTIME if mtime
            file_flags |= FILE_HAS_CRC32 if crc32

            # Build header data with file information
            data = build_file_data(filename, file_size, compressed_size,
                                   file_flags, compression_method, mtime, crc32)
            super(HEADER_TYPE_FILE, flags: flags, data_area_size: compressed_size, header_data: data, extra_area: extra_area)
          end

          private

          def build_file_data(filename, file_size, _compressed_size,
file_flags, compression_method, mtime, crc32)
            data = []

            # File flags (VINT)
            data.concat(VINT.encode(file_flags))

            # Unp size (uncompressed size, VINT)
            data.concat(VINT.encode(file_size))

            # Attributes (VINT) - ALWAYS present in RAR5
            # Use 0x2483 from official RAR (standard regular file with correct permissions)
            data.concat(VINT.encode(0x2483))

            # Mystery VINT with value 0x02 - observed in official RAR
            # This appears after attributes in official archives - ALWAYS present
            data.concat(VINT.encode(0x02))

            # mtime (optional) - only if FILE_HAS_MTIME flag is set
            # RAR5 stores mtime as Unix timestamp (seconds since epoch) in DOS format
            # Format: 4 bytes little-endian (NOT a VINT)
            if file_flags.anybits?(FILE_HAS_MTIME) && mtime
              # Convert Time to Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
              unix_time = mtime.to_i
              # Pack as 32-bit unsigned little-endian
              data.concat([unix_time].pack("V").bytes)
            end

            # Data CRC32 (optional) - only if FILE_HAS_CRC32 flag is set
            # Format: 4 bytes little-endian (NOT a VINT)
            if file_flags.anybits?(FILE_HAS_CRC32) && crc32
              # Pack as 32-bit unsigned little-endian
              data.concat([crc32].pack("V").bytes)
            end

            # Compression info (VINT)
            # Bits 0-5: method (0=STORE, 1-5=LZMA with different levels)
            # Bits 6+: version
            data.concat(VINT.encode(compression_method))

            # Host OS (VINT) - 1 = Unix
            data.concat(VINT.encode(1)) # Unix

            # Name length (VINT)
            name_bytes = filename.encode("UTF-8").bytes
            data.concat(VINT.encode(name_bytes.size))

            # Name
            data.concat(name_bytes)

            data.pack("C*")
          end
        end

        # End of archive header
        class EndHeader < Header
          def initialize
            # End header is minimal
            super(HEADER_TYPE_END, flags: 0)
          end
        end
      end
    end
  end
end
