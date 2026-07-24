# frozen_string_literal: true

module Omnizip
  module Formats
    module Ole
      # OLE format constants
      #
      # Constants for the OLE compound document format including
      # magic bytes, special markers, and format-related values.
      module Constants
        # OLE magic signature (D0CF11E0A1B11AE1)
        MAGIC = "\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1".b

        # Header size in bytes
        HEADER_SIZE = 76

        # Header block size (always 512)
        HEADER_BLOCK_SIZE = 512

        # Allocation table special markers
        AVAIL     = 0xffffffff # Free block
        EOC       = 0xfffffffe # End of chain
        BAT       = 0xfffffffd # Block stores BAT data
        META_BAT  = 0xfffffffc # Block stores Meta BAT

        # End of tree marker for dirents
        EOT = 0xffffffff

        # Default threshold for small block vs big block (4096 bytes)
        DEFAULT_THRESHOLD = 4096

        # Byte order marker for little-endian
        BYTE_ORDER_LE = "\xfe\xff".b

        # Default block sizes
        DEFAULT_BIG_BLOCK_SHIFT   = 9  # 512 bytes
        DEFAULT_SMALL_BLOCK_SHIFT = 6  # 64 bytes

        # Dirent types
        DIRENT_TYPES = {
          0 => :empty,
          1 => :dir,
          2 => :file,
          5 => :root,
        }.freeze

        # Dirent colors for red-black tree
        DIRENT_COLORS = {
          0 => :red,
          1 => :black,
        }.freeze

        # Dirent size in bytes
        DIRENT_SIZE = 128

        # Maximum name length in UTF-16 characters (including null terminator)
        MAX_NAME_LENGTH = 32
      end
    end
  end
end
