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

        # Compression strategies. RLE and FIXED are CRuby-only Zlib
        # constants (JRuby's zlib omits them — found by the JRuby CI
        # leg); the numeric values are fixed by the zlib spec.
        FILTERED = Zlib::FILTERED
        HUFFMAN_ONLY = Zlib::HUFFMAN_ONLY
        RLE = Zlib.const_defined?(:RLE) ? Zlib::RLE : 3
        FIXED = Zlib.const_defined?(:FIXED) ? Zlib::FIXED : 4
        DEFAULT_STRATEGY = Zlib::DEFAULT_STRATEGY

        # Buffer size for streaming operations
        BUFFER_SIZE = 32 * 1024 # 32KB
      end
    end
  end
end
