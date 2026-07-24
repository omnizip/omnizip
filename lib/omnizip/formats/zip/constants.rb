# frozen_string_literal: true

module Omnizip
  module Formats
    module Zip
      # ZIP format constants and signatures
      module Constants
        # File signatures
        LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50
        CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50
        END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06054b50
        ZIP64_END_OF_CENTRAL_DIRECTORY_SIGNATURE = 0x06064b50
        ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE = 0x07064b50
        DATA_DESCRIPTOR_SIGNATURE = 0x08074b50

        # Compression methods
        COMPRESSION_STORE = 0      # No compression
        COMPRESSION_SHRUNK = 1     # Shrunk
        COMPRESSION_REDUCED_1 = 2  # Reduced with compression factor 1
        COMPRESSION_REDUCED_2 = 3  # Reduced with compression factor 2
        COMPRESSION_REDUCED_3 = 4  # Reduced with compression factor 3
        COMPRESSION_REDUCED_4 = 5  # Reduced with compression factor 4
        COMPRESSION_IMPLODED = 6   # Imploded
        COMPRESSION_DEFLATE = 8    # Deflated
        COMPRESSION_DEFLATE64 = 9  # Enhanced Deflating
        COMPRESSION_BZIP2 = 12     # BZIP2
        COMPRESSION_LZMA = 14      # LZMA
        COMPRESSION_ZSTANDARD = 93 # Zstandard
        COMPRESSION_PPMD = 98      # PPMd version I, Rev 1

        # General purpose bit flags
        FLAG_ENCRYPTED = 0x0001
        FLAG_DATA_DESCRIPTOR = 0x0008
        FLAG_STRONG_ENCRYPTION = 0x0040
        FLAG_UTF8 = 0x0800

        # ZIP64 extended information extra field tag
        ZIP64_EXTRA_FIELD_TAG = 0x0001

        # Version needed to extract
        VERSION_DEFAULT = 20       # 2.0 - Default
        VERSION_DEFLATE = 20       # 2.0 - Deflate
        VERSION_ZIP64 = 45         # 4.5 - ZIP64
        VERSION_BZIP2 = 46         # 4.6 - BZIP2
        VERSION_LZMA = 63          # 6.3 - LZMA

        # Made by versions
        VERSION_MADE_BY_UNIX = 3 << 8
        VERSION_MADE_BY_WINDOWS = 0 << 8

        # External file attributes
        ATTR_DIRECTORY = 0x10
        ATTR_ARCHIVE = 0x20

        # Unix permissions
        UNIX_DIR_PERMISSIONS = 0o755 << 16
        UNIX_FILE_PERMISSIONS = 0o644 << 16
        UNIX_SYMLINK_PERMISSIONS = 0o120777 << 16

        # Unix extra field tag (Info-ZIP)
        UNIX_EXTRA_FIELD_TAG = 0x7875

        # Size limits
        ZIP64_LIMIT = 0xFFFFFFFF
        MAX_COMMENT_LENGTH = 0xFFFF
      end
    end
  end
end
