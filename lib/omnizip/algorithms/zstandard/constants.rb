# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

module Omnizip
  module Algorithms
    class Zstandard
      # Constants from RFC 8878 (Zstandard Compression)
      #
      # @see https://datatracker.ietf.org/doc/html/rfc8878
      module Constants
        # Frame Constants
        MAGIC_NUMBER = 0xFD2FB528
        MAGIC_BYTES = [0x28, 0xB5, 0x2F, 0xFD].freeze
        SKIPPABLE_MAGIC_BASE = 0x184D2A50
        SKIPPABLE_MAGIC_MASK = 0xFFFFFFF0

        # Block Types (RFC 8878 Section 3.1.1.2)
        BLOCK_TYPE_RAW = 0
        BLOCK_TYPE_RLE = 1
        BLOCK_TYPE_COMPRESSED = 2
        BLOCK_TYPE_RESERVED = 3
        BLOCK_HEADER_SIZE = 3
        BLOCK_MAX_SIZE = 128 * 1024

        # Literals Block Types (RFC 8878 Section 3.1.1.3.1)
        LITERALS_BLOCK_RAW = 0
        LITERALS_BLOCK_RLE = 1
        LITERALS_BLOCK_COMPRESSED = 2
        LITERALS_BLOCK_TREELESS = 3
        HUFFMAN_MAX_BITS = 11

        # Sequence Compression Modes (RFC 8878 Section 3.1.1.3.2)
        MODE_PREDEFINED = 0
        MODE_RLE = 1
        MODE_FSE = 2
        MODE_REPEAT = 3

        # FSE Accuracy Logs (RFC 8878 Section 4)
        LITERALS_LENGTH_ACCURACY_LOG = 6
        MATCH_LENGTH_ACCURACY_LOG = 6
        OFFSET_ACCURACY_LOG = 5

        # Repeat Offsets (RFC 8878 Section 3.1.2.2.3)
        REPEAT_OFFSET_1 = 1
        REPEAT_OFFSET_2 = 2
        REPEAT_OFFSET_3 = 3
        DEFAULT_REPEAT_OFFSETS = [1, 4, 8].freeze

        # Window Constants (RFC 8878 Section 3.1.1.1.2)
        WINDOW_LOG_MIN = 10
        WINDOW_LOG_MAX = 41

        # Huffman Constants (RFC 8878 Section 4.2.1)
        HUFFMAN_MAX_LOG = 11
        HUFFMAN_MAX_CODE_LENGTH = 11
        HUFFMAN_STANDARD_TABLE_SIZE = 256

        # FSE Table Limits (RFC 8878 Section 4.1)
        FSE_MAX_ACCURACY_LOG = 9
        FSE_MIN_ACCURACY_LOG = 5

        # Compression levels
        MIN_LEVEL = 1
        MAX_LEVEL = 22
        DEFAULT_LEVEL = 3

        # Buffer size for streaming operations
        BUFFER_SIZE = 128 * 1024 # 128KB

        # Literal length codes (RFC 8878 Table 9)
        # Each entry: [baseline, extra_bits]
        LITERAL_LENGTH_TABLE = [
          [0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [5, 0], [6, 0], [7, 0],
          [8, 0], [9, 0], [10, 0], [11, 0], [12, 0], [13, 0], [14, 0], [15, 0],
          [16, 1], [18, 1], [20, 1], [22, 1], [24, 1], [28, 1], [32, 1], [40, 1],
          [48, 1], [64, 1], [128, 2], [256, 2], [512, 2], [1024, 2], [2048, 2],
          [4096, 2], [8192, 2], [16384, 3], [32768, 3], [65536, 3]
        ].freeze

        # Match length codes (RFC 8878 Table 10)
        # Each entry: [baseline, extra_bits]
        MATCH_LENGTH_TABLE = [
          [3, 0], [4, 0], [5, 0], [6, 0], [7, 0], [8, 0], [9, 0], [10, 0],
          [11, 0], [12, 0], [13, 0], [14, 0], [15, 0], [16, 0], [17, 0], [18, 0],
          [19, 0], [20, 0], [21, 0], [22, 0], [23, 0], [24, 0], [25, 0], [26, 0],
          [27, 0], [28, 0], [29, 0], [30, 0], [31, 0], [32, 0], [33, 0], [34, 0],
          [35, 1], [37, 1], [39, 1], [41, 1], [43, 1], [47, 1], [51, 1], [59, 1],
          [67, 1], [83, 1], [99, 1], [131, 2], [195, 2], [259, 2], [323, 2],
          [387, 2], [451, 2], [515, 2], [579, 2], [643, 2], [707, 2], [771, 2],
          [835, 2], [899, 2], [963, 2], [1027, 2], [1283, 2], [1539, 2],
          [1795, 2], [2051, 2], [2307, 2], [2563, 2]
        ].freeze

        # Predefined FSE distribution for literals length (RFC 8878 Section 4.1.3)
        PREDEFINED_LL_DISTRIBUTION = [
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
          0, 0, 0, 0
        ].freeze

        # Predefined FSE distribution for match length (RFC 8878 Section 4.1.3)
        # Sum = 64 (must equal 2^6 = 64)
        PREDEFINED_ML_DISTRIBUTION = [
          1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ].freeze

        # Predefined FSE distribution for offset (RFC 8878 Section 4.1.3)
        PREDEFINED_OFFSET_DISTRIBUTION = [
          1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ].freeze
      end
    end
  end
end
