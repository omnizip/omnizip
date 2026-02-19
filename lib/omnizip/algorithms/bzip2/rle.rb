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
    class BZip2 < Algorithm
      # Run-Length Encoding (RLE) for BZip2
      #
      # This is a BZip2-specific RLE variant that encodes runs of
      # identical bytes. After MTF, the data often contains long runs
      # of zeros, which RLE compresses efficiently.
      #
      # BZip2 RLE encoding scheme:
      # - Runs of 4-259 identical bytes are encoded as:
      #   [byte, byte, byte, byte, count-4]
      # - Where count is 0-255 representing 4-259 repetitions
      # - Runs < 4 are left unencoded
      # - This scheme avoids ambiguity in decoding
      class Rle
        # Maximum run length (4 + 255)
        MAX_RUN_LENGTH = 259

        # Minimum run length for encoding
        MIN_RUN_LENGTH = 4

        # Encode data using BZip2 RLE
        #
        # @param data [String] Input data to encode
        # @return [String] RLE-encoded data
        def encode(data)
          return "".b if data.empty?

          result = []
          i = 0

          while i < data.length
            byte = data.getbyte(i)
            run_length = count_run(data, i)

            if run_length >= MIN_RUN_LENGTH
              # Encode run: emit 4 copies + extra count
              extra = [run_length - MIN_RUN_LENGTH, 255].min
              4.times { result << byte }
              result << extra
              i += MIN_RUN_LENGTH + extra
            else
              # No run, emit single byte
              result << byte
              i += 1
            end
          end

          result.pack("C*")
        end

        # Decode RLE-encoded data
        #
        # @param data [String] RLE-encoded data
        # @return [String] Decoded data
        def decode(data)
          return "".b if data.empty?

          result = []
          i = 0
          skip_count = 0

          while i < data.length
            byte = data.getbyte(i)
            result << byte
            i += 1

            # Decrement skip counter if active
            if skip_count.positive?
              skip_count -= 1
              next
            end

            # Check for run encoding (4 consecutive identical bytes)
            next unless i >= 4 && consecutive_match?(result, byte, 4)

            # Read run count
            break if i >= data.length

            count = data.getbyte(i)
            i += 1

            # Emit additional copies
            count.times { result << byte }

            # Skip checking for next 3 bytes (need 4 to form a run)
            skip_count = 3
          end

          result.pack("C*")
        end

        private

        # Count run length starting at given position
        #
        # @param data [String] Input data
        # @param start [Integer] Starting position
        # @return [Integer] Run length
        def count_run(data, start)
          byte = data.getbyte(start)
          count = 1

          (start + 1).upto([start + MAX_RUN_LENGTH - 1,
                            data.length - 1].min) do |i|
            break if data.getbyte(i) != byte

            count += 1
          end

          count
        end

        # Check if last n bytes in array match the given byte
        #
        # @param array [Array<Integer>] Byte array
        # @param byte [Integer] Byte to match
        # @param count [Integer] Number of bytes to check
        # @return [Boolean] True if last n bytes match
        def consecutive_match?(array, byte, count)
          return false if array.length < count

          array[-count..].all?(byte)
        end
      end
    end
  end
end
