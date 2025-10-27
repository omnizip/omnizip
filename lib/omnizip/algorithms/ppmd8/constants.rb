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
    class PPMd8 < PPMdBase
      # Constants specific to PPMd8 algorithm
      #
      # PPMd8 adds restoration methods and enhanced memory management
      # compared to PPMd7.
      module Constants
        # Restoration method constants
        RESTORE_METHOD_RESTART = 0
        RESTORE_METHOD_CUT_OFF = 1
        DEFAULT_RESTORE_METHOD = RESTORE_METHOD_RESTART

        # Probability scaling factors
        PROB_TOTAL = 2048
        MAX_FREQ = 124
        INIT_ESCAPE_FREQ = 1

        # Context management
        SEE_CONTEXTS = 25
        SUFFIX_CONTEXTS = 32

        # Update intervals
        INT_BITS = 7
        PERIOD_BITS = 7
        BIN_SCALE = 1 << 13
        INTERVAL = 1 << INT_BITS

        # Memory management
        UNIT_SIZE = 12
        MAX_STATES = 256
        UNIT_ALLOC_SIZE = 12

        # PPMd8-specific: glue counting threshold
        GLUE_COUNT_THRESHOLD = 255
      end
    end
  end
end
