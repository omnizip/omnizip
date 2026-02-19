# frozen_string_literal: true

module Omnizip
  module Algorithms
    # LZMA2 Format Constants (from XZ Utils specification)
    module LZMA2Const
      # Maximum size of compressed data per chunk (excluding headers)
      CHUNK_MAX = 65536 # 64 KB

      # Maximum size of uncompressed data per chunk
      # Limited by 16-bit size field in LZMA2 header (stores size-1)
      # Max value is 0xFFFF + 1 = 65536 bytes
      UNCOMPRESSED_MAX = 65536 # 64 KB

      # Maximum size of LZMA2 chunk header
      HEADER_MAX = 6

      # Size of uncompressed chunk header
      HEADER_UNCOMPRESSED = 3

      # Control byte values
      CONTROL_END = 0x00                    # End of stream marker
      CONTROL_UNCOMPRESSED_RESET = 0x01     # Uncompressed with dict reset
      CONTROL_UNCOMPRESSED = 0x02           # Uncompressed without reset
      CONTROL_LZMA_MIN = 0x80               # Minimum LZMA control byte

      # Control byte flags (for LZMA chunks)
      FLAG_UNCOMPRESSED_SIZE = 0x80         # Base flag for LZMA chunks
      FLAG_RESET_STATE = 0x20               # Reset LZMA state
      FLAG_RESET_PROPERTIES = 0x40          # Reset properties + state
      FLAG_RESET_DICT = 0x60                # Reset dict + properties + state

      # Dictionary size encoding constants
      DICT_SIZE_MIN = 4096 # 4 KB minimum
      DICT_SIZE_MAX = 0xFFFFFFFF # 4 GB maximum
    end

    # Alias for backward compatibility
    LZMA2Constants = LZMA2Const
  end
end
