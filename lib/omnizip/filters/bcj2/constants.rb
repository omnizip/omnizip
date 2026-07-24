# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

module Omnizip
  module Filters
    module Bcj2Constants
      # Number of output streams
      NUM_STREAMS = 4

      # Stream indices
      STREAM_MAIN = 0 # Main data stream (non-convertible bytes)
      STREAM_CALL = 1 # CALL instruction addresses (E8)
      STREAM_JUMP = 2 # JUMP instruction addresses (E9)
      STREAM_RC = 3   # Range coder probability stream

      # x86 opcodes
      OPCODE_CALL = 0xE8 # CALL instruction
      OPCODE_JUMP = 0xE9 # JUMP instruction

      # Size of x86 address (4 bytes, little-endian)
      ADDRESS_SIZE = 4

      # Range coder constants
      TOP_VALUE = 1 << 24            # Range normalization threshold
      BIT_MODEL_TOTAL_BITS = 11      # Probability model bits
      BIT_MODEL_TOTAL = 1 << BIT_MODEL_TOTAL_BITS
      MOVE_BITS = 5                  # Probability update shift

      # Number of probability models (2 + 256)
      # - 2 for general cases (not E8/E9, or 0F8x pattern)
      # - 256 for byte-specific models when processing E8
      NUM_PROBS = 2 + 256

      # Initial probability value (50%)
      INITIAL_PROB = BIT_MODEL_TOTAL >> 1
    end
  end
end
