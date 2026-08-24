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
      module FSE
        # Reverse-direction bit reader matching the zstd C reference
        # `BIT_DStream` (lib/common/bitstream.h).
        #
        # The bitstream is written forward by the encoder but read
        # BACKWARDS: bytes are consumed from the last toward the first,
        # and within each byte bits are consumed MSB-first. The reader
        # keeps a 64-bit container (little-endian window onto 8 bytes)
        # and takes bits from the high end after `bits_consumed`.
        #
        # The last byte holds a 1 end-mark bit with 0-7 padding zero
        # bits above it; the last byte can therefore never be 0x00.
        class BitStream
          MASK64 = 0xFFFFFFFFFFFFFFFF

          # Reload statuses mirroring C's BIT_DStream_status.
          UNFINISHED = :unfinished
          END_OF_BUFFER = :end_of_buffer
          COMPLETED = :completed
          OVERFLOW = :overflow

          attr_reader :data

          # @param data [String] the full bitstream bytes (binary)
          def initialize(data)
            @data = data
            n = data.bytesize
            last = n.positive? ? data.getbyte(n - 1) : 0
            end_mark = last.positive? ? 8 - Constants.highbit32(last) : 0

            if n >= 8
              @ptr = n - 8
              @container = read_le64(@ptr)
              @bits_consumed = end_mark
            else
              @ptr = 0
              @container = 0
              n.times { |i| @container |= data.getbyte(i) << (i * 8) }
              @bits_consumed = end_mark + ((8 - n) * 8)
            end
          end

          # Read `count` bits, first-read bit becoming the value's MSB
          # (little-endian value semantics per RFC 8878 §4.1).
          #
          # @param count [Integer] 0..32
          # @return [Integer]
          def read_bits(count)
            return 0 if count.zero?

            shift_left = @bits_consumed & 63
            shift_right = (64 - count) & 63
            result = ((@container << shift_left) & MASK64) >> shift_right
            @bits_consumed += count
            result & ((1 << count) - 1)
          end

          # Peek `count` bits without consuming.
          def peek_bits(count)
            saved_ptr = @ptr
            saved_container = @container
            saved_consumed = @bits_consumed
            result = read_bits(count)
            @ptr = saved_ptr
            @container = saved_container
            @bits_consumed = saved_consumed
            result
          end

          # Reload the container after enough bits have been consumed,
          # mirroring C's BIT_reloadDStream.
          def reload
            return if @bits_consumed < 8

            if @ptr >= 8
              bytes_consumed = @bits_consumed >> 3
              @ptr -= bytes_consumed
              @ptr = 0 if @ptr.negative?
              @bits_consumed &= 7
              load_container
            elsif @ptr.zero?
              # No earlier bytes to load; leave the container as is.
            else
              nb_bytes = @bits_consumed >> 3
              actual_bytes = [nb_bytes, @ptr].min
              @ptr -= actual_bytes
              @bits_consumed -= actual_bytes * 8
              load_container
            end
          end

          # Full reload that also reports the C reload status.
          #
          # @return [Symbol] one of UNFINISHED, END_OF_BUFFER, COMPLETED,
          #   OVERFLOW
          def reload_status
            return OVERFLOW if @bits_consumed > 64

            if @ptr >= 8
              bytes_consumed = @bits_consumed >> 3
              @ptr -= bytes_consumed
              @ptr = 0 if @ptr.negative?
              @bits_consumed &= 7
              load_container
              return UNFINISHED
            end
            return END_OF_BUFFER if @ptr.zero?

            nb_bytes = @bits_consumed >> 3
            actual_bytes = [nb_bytes, @ptr].min
            @ptr -= actual_bytes
            @bits_consumed -= actual_bytes * 8
            load_container
            actual_bytes < nb_bytes ? END_OF_BUFFER : UNFINISHED
          end

          # Skip to the next byte boundary (toward the stream start).
          def align_to_byte
            remainder = @bits_consumed % 8
            return if remainder.zero?

            @bits_consumed += 8 - remainder
            reload if @bits_consumed >= 8
          end

          # Bits not yet consumed, counting from the end of the data.
          def remaining_bits
            total = @data.bytesize * 8
            consumed = bits_consumed_so_far
            total >= consumed ? total - consumed : 0
          end

          def exhausted?
            remaining_bits.zero?
          end

          private

          def bits_consumed_so_far
            bytes_after_window = @data.bytesize - (@ptr + 8)
            bytes_after_window = 0 if bytes_after_window.negative?
            (bytes_after_window * 8) + @bits_consumed
          end

          def read_le64(offset)
            v = 0
            8.times { |i| v |= @data.getbyte(offset + i) << (i * 8) }
            v
          end

          def load_container
            @container = read_le64(@ptr)
          end
        end
      end
    end
  end
end
