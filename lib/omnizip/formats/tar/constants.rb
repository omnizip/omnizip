# frozen_string_literal: true

module Omnizip
  module Formats
    module Tar
      # TAR format constants
      module Constants
        # TAR header size (POSIX ustar format)
        HEADER_SIZE = 512

        # Block size for TAR archives
        BLOCK_SIZE = 512

        # Type flags for TAR entries
        TYPE_REGULAR = "0"        # Regular file
        TYPE_HARD_LINK = "1"      # Hard link
        TYPE_SYMLINK = "2"        # Symbolic link
        TYPE_CHAR_DEVICE = "3"    # Character device
        TYPE_BLOCK_DEVICE = "4"   # Block device
        TYPE_DIRECTORY = "5"      # Directory
        TYPE_FIFO = "6"           # FIFO
        TYPE_CONTIGUOUS = "7"     # Contiguous file
        TYPE_EXTENDED = "x"       # Extended header
        TYPE_GLOBAL_EXTENDED = "g" # Global extended header
        TYPE_GNU_LONGNAME = "L"   # GNU long name
        TYPE_GNU_LONGLINK = "K"   # GNU long link

        # POSIX ustar magic value
        USTAR_MAGIC = "ustar"

        # POSIX ustar version
        USTAR_VERSION = "00"

        # Maximum file size (8GB - 1 for base-8 12-byte field)
        MAX_FILE_SIZE = (8**12) - 1

        # Field positions in TAR header
        NAME_OFFSET = 0
        NAME_SIZE = 100
        MODE_OFFSET = 100
        MODE_SIZE = 8
        UID_OFFSET = 108
        UID_SIZE = 8
        GID_OFFSET = 116
        GID_SIZE = 8
        SIZE_OFFSET = 124
        SIZE_SIZE = 12
        MTIME_OFFSET = 136
        MTIME_SIZE = 12
        CHECKSUM_OFFSET = 148
        CHECKSUM_SIZE = 8
        TYPEFLAG_OFFSET = 156
        TYPEFLAG_SIZE = 1
        LINKNAME_OFFSET = 157
        LINKNAME_SIZE = 100
        MAGIC_OFFSET = 257
        MAGIC_SIZE = 6
        VERSION_OFFSET = 263
        VERSION_SIZE = 2
        UNAME_OFFSET = 265
        UNAME_SIZE = 32
        GNAME_OFFSET = 297
        GNAME_SIZE = 32
        DEVMAJOR_OFFSET = 329
        DEVMAJOR_SIZE = 8
        DEVMINOR_OFFSET = 337
        DEVMINOR_SIZE = 8
        PREFIX_OFFSET = 345
        PREFIX_SIZE = 155
      end
    end
  end
end
