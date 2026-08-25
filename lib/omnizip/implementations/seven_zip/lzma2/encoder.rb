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
  module Implementations
    module SevenZip
      module LZMA2
        # 7-Zip LZMA2 encoder.
        #
        # The LZMA2 stream itself is format-identical to the raw LZMA2
        # layer of the XZ Utils encoder (chunks + 0x00 end marker); the
        # 7-Zip container carries the method properties, so no property
        # byte is written into the data stream (standalone: false).
        #
        # This is a thin subclass rather than a copy: the XZ Utils
        # encoder carries the fixes for global pos_state across
        # chunks, announced state resets, the 64 KiB compressed-chunk
        # cap (16-bit size field) and the range-encoder symbol-queue
        # drain, which a duplicated implementation silently missed.
        class Encoder < Implementations::XZUtils::LZMA2::Encoder
          # 7-Zip callers pass the same option keys; only the property
          # byte default differs (the container describes the coder).
          def initialize(options = {})
            super({ standalone: false }.merge(options))
          end

          # Get implementation identifier.
          #
          # @return [Symbol] :seven_zip_sdk
          def implementation_name
            :seven_zip_sdk
          end
        end
      end
    end
  end
end
