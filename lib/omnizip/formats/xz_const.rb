# frozen_string_literal: true

module Omnizip
  module Formats
    # XZ Format Constants (from XZ Utils specification)
    module XzConst
      # XZ Stream magic bytes
      MAGIC = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].freeze

      # Footer magic bytes
      FOOTER_MAGIC = [0x59, 0x5A].freeze

      # Header and footer sizes
      STREAM_HEADER_SIZE = 12
      STREAM_FOOTER_SIZE = 12

      # Stream flags size
      STREAM_FLAGS_SIZE = 2

      # Block header constraints
      BLOCK_HEADER_SIZE_MIN = 8
      BLOCK_HEADER_SIZE_MAX = 1024

      # Backward size constraints
      BACKWARD_SIZE_MIN = 4
      BACKWARD_SIZE_MAX = (1 << 34) - 4 # ~17 GB

      # Check types (from lzma/check.h)
      CHECK_NONE = 0
      CHECK_CRC32 = 1
      CHECK_CRC64 = 4
      CHECK_SHA256 = 10

      # VLI (Variable Length Integer) constants
      VLI_UNKNOWN = 0xFFFFFFFFFFFFFFFF # LZMA_VLI_UNKNOWN
      VLI_BYTES_MAX = 9

      # Filter IDs (from lzma/check.h)
      # XZ Utils uses LZMA_FILTER_LZMA2 = 0x21 (as defined in lzma/lzma12.h:61)
      FILTER_LZMA2 = 0x21

      # Maximum number of filters in a chain
      FILTERS_MAX = 4

      # Index indicator (byte value that signals start of index)
      INDEX_INDICATOR = 0x00
    end
  end
end
