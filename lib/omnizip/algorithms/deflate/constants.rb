# frozen_string_literal: true

require "zlib"

module Omnizip
  module Algorithms
    class Deflate
      # Constants for Deflate algorithm
      module Constants
        # Compression levels
        NO_COMPRESSION = Zlib::NO_COMPRESSION
        BEST_SPEED = Zlib::BEST_SPEED
        BEST_COMPRESSION = Zlib::BEST_COMPRESSION
        DEFAULT_COMPRESSION = Zlib::DEFAULT_COMPRESSION

        # Compression strategies
        FILTERED = Zlib::FILTERED
        HUFFMAN_ONLY = Zlib::HUFFMAN_ONLY
        RLE = Zlib::RLE
        FIXED = Zlib::FIXED
        DEFAULT_STRATEGY = Zlib::DEFAULT_STRATEGY

        # Buffer size for streaming operations
        BUFFER_SIZE = 32 * 1024 # 32KB
      end
    end
  end
end
