# frozen_string_literal: true

module Omnizip
  module Algorithms
    class Zstandard
      # Constants for Zstandard algorithm
      module Constants
        # Compression levels (Zstd supports 1-22)
        MIN_LEVEL = 1
        MAX_LEVEL = 22
        DEFAULT_LEVEL = 3

        # Fast compression levels
        FAST_LEVEL = 1
        BALANCED_LEVEL = 3

        # Maximum compression level
        ULTRA_LEVEL = 22

        # Buffer size for streaming operations
        BUFFER_SIZE = 128 * 1024 # 128KB
      end
    end
  end
end
