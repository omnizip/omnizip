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
    class LZMA
      # LZMA algorithm constants
      #
      # This module contains all constants used by the LZMA algorithm,
      # including range coding parameters, probability models, and
      # compression limits.
      module Constants
        # Range coder constants
        # TOP: Threshold for range normalization (2^24)
        TOP = 0x01000000

        # BIT_MODEL_TOTAL: Total probability range for bit models (2^11)
        BIT_MODEL_TOTAL = 0x800

        # BIT_MODEL_MOVE_BITS: Number of bits to shift for prob updates
        MOVE_BITS = 5

        # INIT_PROBS: Initial probability value (0.5 probability)
        INIT_PROBS = BIT_MODEL_TOTAL >> 1

        # Number of bits used in direct bit encoding
        NUM_DIRECT_BITS = 8

        # LZMA state constants
        # Number of position bits for literal context (lp)
        NUM_LIT_POS_BITS_MAX = 4

        # Number of literal context bits (lc)
        NUM_LIT_CONTEXT_BITS_MAX = 8

        # Number of position bits (pb)
        NUM_POS_BITS_MAX = 4

        # Number of LZMA states (from state machine)
        NUM_STATES = 12

        # Dictionary size limits
        DICT_SIZE_MIN = 1 << 12  # 4KB
        DICT_SIZE_MAX = 1 << 30  # 1GB

        # Match length constants
        MATCH_LEN_MIN = 2
        MATCH_LEN_MAX = 273

        # Number of distance slots
        NUM_DIST_SLOTS = 64

        # Position states
        POS_STATES_MAX = 1 << NUM_POS_BITS_MAX

        # Literal coder size
        LIT_SIZE_MAX = (1 << (NUM_LIT_POS_BITS_MAX +
                                NUM_LIT_CONTEXT_BITS_MAX))

        # Number of length to position states
        NUM_LEN_TO_POS_STATES = 4

        # Compression levels
        COMPRESSION_LEVEL_MIN = 0
        COMPRESSION_LEVEL_MAX = 9
        COMPRESSION_LEVEL_DEFAULT = 5

        # End of stream marker
        EOS_MARKER = true

        # SDK-specific encoding constants
        # Length encoding constants
        NUM_LEN_LOW_BITS = 3
        NUM_LEN_MID_BITS = 3
        NUM_LEN_HIGH_BITS = 8
        LEN_LOW_SYMBOLS = 1 << NUM_LEN_LOW_BITS
        LEN_MID_SYMBOLS = 1 << NUM_LEN_MID_BITS
        LEN_HIGH_SYMBOLS = 1 << NUM_LEN_HIGH_BITS

        # Distance encoding constants
        NUM_DIST_SLOT_BITS = 6
        DIST_ALIGN_BITS = 4
        DIST_ALIGN_SIZE = 1 << DIST_ALIGN_BITS
        START_POS_MODEL_INDEX = 4
        END_POS_MODEL_INDEX = 14
        NUM_FULL_DISTANCES = 1 << (END_POS_MODEL_INDEX >> 1)

        # Distance slot calculation helper
        DIST_SLOT_FAST_LIMIT = 1 << (NUM_DIST_SLOT_BITS + 1)
      end
    end
  end
end
