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
    class PPMd7 < Algorithm
      # Constants for PPMd7 algorithm
      #
      # PPMd7 uses context-based statistical compression with
      # maximum context orders typically ranging from 2 to 16.
      module Constants
        # Maximum context order (model order)
        MAX_ORDER = 16
        MIN_ORDER = 2
        DEFAULT_ORDER = 6

        # Memory allocation constants
        MIN_MEM_SIZE = 1 << 20  # 1 MB minimum
        MAX_MEM_SIZE = 1 << 30  # 1 GB maximum
        DEFAULT_MEM_SIZE = 1 << 24 # 16 MB default

        # Probability scaling factors
        PROB_TOTAL = 2048
        MAX_FREQ = 124
        INIT_ESCAPE_FREQ = 1

        # Symbol alphabet size
        ALPHABET_SIZE = 256

        # Context node structure sizes
        UNIT_SIZE = 12

        # Maximum number of states per context
        MAX_STATES = 256

        # Escape symbol handling
        SEE_CONTEXTS = 25
        SUFFIX_CONTEXTS = 32

        # Update intervals for probability models
        INT_BITS = 7
        PERIOD_BITS = 7
        BIN_SCALE = 1 << 13
        INTERVAL = 1 << INT_BITS

        # Memory unit allocation
        UNIT_ALLOC_SIZE = 12

        # Range coder constants (inherited from arithmetic coding)
        TOP_VALUE = 1 << 24
        BOT_VALUE = 1 << 15
      end
    end
  end
end
