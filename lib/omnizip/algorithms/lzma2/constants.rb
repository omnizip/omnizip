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
    class LZMA2
      # LZMA2 algorithm constants
      #
      # This module contains all constants used by the LZMA2 algorithm,
      # including chunk sizes, control byte values, and dictionary size
      # encoding parameters.
      module Constants
        # Chunk size limits (in bytes)
        # Minimum chunk size: 64KB
        CHUNK_SIZE_MIN = 64 * 1024

        # Maximum chunk size: 64MB (for single-threaded operation)
        CHUNK_SIZE_MAX = 64 * 1024 * 1024

        # Default chunk size: 2MB (good balance for most use cases)
        CHUNK_SIZE_DEFAULT = 2 * 1024 * 1024

        # Control byte values for chunk types
        # End of stream marker (0x00)
        CONTROL_END = 0x00

        # Uncompressed chunk, dictionary reset (0x01)
        CONTROL_UNCOMPRESSED_RESET = 0x01

        # Uncompressed chunk, no dictionary reset (0x02)
        CONTROL_UNCOMPRESSED_NO_RESET = 0x02

        # LZMA chunk, dictionary reset, new properties (0x80 + size info)
        CONTROL_LZMA_RESET_PROPS = 0x80

        # LZMA chunk, dictionary reset, reuse properties (0xC0 + size info)
        CONTROL_LZMA_RESET_NO_PROPS = 0xC0

        # LZMA chunk, no dictionary reset (0xE0 + size info)
        CONTROL_LZMA_NO_RESET = 0xE0

        # Dictionary size encoding
        # Minimum dictionary size: 4KB
        DICT_SIZE_MIN = 1 << 12

        # Maximum dictionary size: 1GB
        DICT_SIZE_MAX = 1 << 30

        # Property byte encoding
        # The single property byte encodes dictionary size
        # Formula: dictSize = 2^(11 + props/2) + 2^11 * (props%2)
        # This gives dictionary sizes from 4KB to 4GB
        PROP_DICT_MIN = 0
        PROP_DICT_MAX = 40

        # Compression efficiency threshold
        # If compressed size is not at least this percent smaller,
        # store uncompressed (0.99 = must be 1% smaller)
        COMPRESSION_THRESHOLD = 0.99

        # Maximum uncompressed chunk size in chunk header
        UNCOMPRESSED_SIZE_MAX = 0xFFFF

        # Size field mask for control bytes
        SIZE_MASK = 0x1F

        # Dictionary reset bit mask
        RESET_MASK = 0x40

        # New properties bit mask
        PROPS_MASK = 0x20
      end
    end
  end
end
