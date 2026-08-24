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
        HUF_SYMBOLVALUE_MAX = 255

        # FSE Table Limits (RFC 8878 Section 4.1)
        FSE_MAX_ACCURACY_LOG = 9
        FSE_MIN_ACCURACY_LOG = 5
        FSE_DEFAULT_TABLELOG = 6

        # Compression levels
        MIN_LEVEL = 1
        MAX_LEVEL = 22
        DEFAULT_LEVEL = 3

        # Buffer size for streaming operations
        BUFFER_SIZE = 128 * 1024 # 128KB

        # Literal length codes (RFC 8878 Table: literals length codes)
        # Each entry: [baseline, extra_bits]
        LITERAL_LENGTH_TABLE = [
          [0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [5, 0], [6, 0], [7, 0],
          [8, 0], [9, 0], [10, 0], [11, 0], [12, 0], [13, 0], [14, 0], [15, 0],
          [16, 1], [18, 1], [20, 1], [22, 1], [24, 2], [28, 2], [32, 3], [40, 3],
          [48, 4], [64, 6], [128, 7], [256, 8], [512, 9], [1024, 10], [2048, 11],
          [4096, 12], [8192, 13], [16384, 14], [32768, 15], [65536, 16]
        ].freeze

        # Match length codes (RFC 8878 Table: match length codes, 53 entries)
        # Each entry: [baseline, extra_bits]
        MATCH_LENGTH_TABLE = [
          [3, 0], [4, 0], [5, 0], [6, 0], [7, 0], [8, 0], [9, 0], [10, 0],
          [11, 0], [12, 0], [13, 0], [14, 0], [15, 0], [16, 0], [17, 0], [18, 0],
          [19, 0], [20, 0], [21, 0], [22, 0], [23, 0], [24, 0], [25, 0], [26, 0],
          [27, 0], [28, 0], [29, 0], [30, 0], [31, 0], [32, 0], [33, 0], [34, 0],
          [35, 1], [37, 1], [39, 1], [41, 1], [43, 2], [47, 2], [51, 3], [59, 3],
          [67, 4], [83, 4], [99, 5], [131, 7], [259, 8], [515, 9], [1027, 10],
          [2051, 11], [4099, 12], [8195, 13], [16387, 14], [32771, 15], [65539, 16]
        ].freeze

        # Offset codes (RFC 8878 Section 3.1.2.2.3.2)
        # OF_BASE[c] + read(c bits) = match distance for c >= 2; codes 0 and
        # 1 are the repeat-offset specials handled by the executor.
        OF_BASE = [
          0, 1, 1, 5, 13, 29, 61, 125, 253, 509, 1021, 2045, 4093, 8189,
          16381, 32765, 65533, 131069, 262141, 524285, 1048573, 2097149,
          4194301, 8388605, 16777213, 33554429, 67108861, 134217725,
          268435453, 536870909, 1073741821, 2147483645
        ].freeze
        OF_BITS = (0..31).to_a.freeze

        # Predefined FSE distributions (RFC 8878 Section 4.1.3, matching
        # the zstd C reference). -1 marks a "less than 1" probability that
        # occupies a single cell at the top of the table.
        PREDEFINED_LL_DISTRIBUTION = [
          4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
          2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
          -1, -1, -1, -1
        ].freeze

        # Sum: 4+3+2*11+1*3 + 2*8+3+2*2+1*5 = 32 + 32 = 64 = 2^6
        PREDEFINED_ML_DISTRIBUTION = [
          1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
          -1, -1, -1, -1, -1
        ].freeze

        # Sum: 27 positive + 5 low-probability = 32 = 2^5
        PREDEFINED_OFFSET_DISTRIBUTION = [
          1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
          1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, 0, 0, 0
        ].freeze

        # floor(log2(x)); 0 for x == 0 (C ZSTD_highbit32 defensive value)
        def self.highbit32(value)
          value.zero? ? 0 : value.bit_length - 1
        end
      end
    end
  end
end
