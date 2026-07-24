# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # RAR format constants
      module Constants
        # RAR signatures
        RAR4_SIGNATURE = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].freeze
        RAR5_SIGNATURE = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].freeze

        # Block types (RAR4)
        BLOCK_MARKER = 0x72
        BLOCK_ARCHIVE = 0x73
        BLOCK_FILE = 0x74
        BLOCK_COMMENT = 0x75
        BLOCK_OLD_EXTRA = 0x76
        BLOCK_OLD_SUBBLOCK = 0x77
        BLOCK_OLD_RECOVERY = 0x78
        BLOCK_OLD_AUTH = 0x79
        BLOCK_SUBBLOCK = 0x7A
        BLOCK_ENDARC = 0x7B

        # Archive flags
        ARCHIVE_VOLUME = 0x0001
        ARCHIVE_COMMENT = 0x0002
        ARCHIVE_LOCKED = 0x0004
        ARCHIVE_SOLID = 0x0008
        ARCHIVE_NEW_NAMING = 0x0010
        ARCHIVE_AUTH_INFO = 0x0020
        ARCHIVE_RECOVERY = 0x0040
        ARCHIVE_ENCRYPTED = 0x0080
        ARCHIVE_FIRST_VOLUME = 0x0100

        # File flags
        FILE_SPLIT_BEFORE = 0x0001
        FILE_SPLIT_AFTER = 0x0002
        FILE_ENCRYPTED = 0x0004
        FILE_COMMENT = 0x0008
        FILE_SOLID = 0x0010
        FILE_DIRECTORY = 0x00E0
        FILE_LARGE = 0x0100
        FILE_UNICODE = 0x0200
        FILE_SALT = 0x0400
        FILE_VERSION = 0x0800
        FILE_EXT_TIME = 0x1000

        # RAR5 header types
        RAR5_HEADER_MAIN = 1
        RAR5_HEADER_FILE = 2
        RAR5_HEADER_SERVICE = 3
        RAR5_HEADER_ENCRYPTION = 4
        RAR5_HEADER_END = 5

        # RAR5 flags
        RAR5_FLAG_EXTRA_AREA = 0x0001
        RAR5_FLAG_DATA_AREA = 0x0002
        RAR5_FLAG_UNKNOWN_BLOCKS = 0x0004
        RAR5_FLAG_DATA_INHERITED = 0x0008
        RAR5_FLAG_CHILD_BLOCKS = 0x0010
        RAR5_FLAG_IS_DIR = 0x0020
        RAR5_FLAG_MULTI_VOLUME = 0x0001

        # Compression methods
        METHOD_STORE = 0x30
        METHOD_FASTEST = 0x31
        METHOD_FAST = 0x32
        METHOD_NORMAL = 0x33
        METHOD_GOOD = 0x34
        METHOD_BEST = 0x35

        # Host OS
        OS_MSDOS = 0
        OS_OS2 = 1
        OS_WIN32 = 2
        OS_UNIX = 3
        OS_MACOS = 4
        OS_BEOS = 5
      end
    end
  end
end
