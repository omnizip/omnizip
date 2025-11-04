# frozen_string_literal: true

module Omnizip
  module Algorithms
    class Deflate64
      # Constants for Deflate64 (Enhanced Deflate) algorithm
      module Constants
        # Dictionary/window size - 64KB vs 32KB in standard Deflate
        DICTIONARY_SIZE = 65_536

        # Match length constraints
        MAX_MATCH_LENGTH = 258
        MIN_MATCH_LENGTH = 3
        MAX_DISTANCE = DICTIONARY_SIZE - 1

        # Huffman coding constants
        LITERAL_CODES = 286
        DISTANCE_CODES = 30
        LENGTH_CODES = 19

        # Block types
        BLOCK_TYPE_STORED = 0
        BLOCK_TYPE_FIXED = 1
        BLOCK_TYPE_DYNAMIC = 2

        # End of block marker
        END_OF_BLOCK = 256

        # Maximum code lengths
        MAX_LITERAL_CODE_LENGTH = 15
        MAX_DISTANCE_CODE_LENGTH = 15

        # Hash table size for LZ77
        HASH_SIZE = 65_536
        HASH_SHIFT = 5

        # Search limits
        MAX_CHAIN_LENGTH = 4096
        GOOD_MATCH = 32
        NICE_MATCH = 258
        MAX_LAZY_MATCH = 258
      end
    end
  end
end