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
  module Formats
    module Rar
      module Compression
        # Bit-level I/O stream for RAR compression algorithms
        #
        # Provides methods to read and write individual bits from byte streams.
        # This is a shared utility used by PPMd, LZ77+Huffman, and other RAR
        # compression algorithms that need bit-level access.
        #
        # Responsibilities:
        # - ONE responsibility: Bit-level I/O operations
        # - Read bits from byte stream
        # - Write bits to byte stream
        # - Manage bit buffer and byte alignment
        class BitStream
          # Initialize a new bit stream
          #
          # @param io [IO] The underlying byte stream
          # @param mode [Symbol] :read or :write
          def initialize(io, mode = :read)
            @io = io
            @mode = mode
            @buffer = 0
            @bits_in_buffer = 0
          end

          # Read specified number of bits
          #
          # @param count [Integer] Number of bits to read (1-32)
          # @return [Integer] The bits read as an integer
          def read_bits(count)
            unless @mode == :read
              raise ArgumentError,
                    "Can only read in read mode"
            end
            raise ArgumentError, "Count must be 1-32" unless count.between?(1,
                                                                            32)

            result = 0

            count.times do
              result = (result << 1) | read_bit
            end

            result
          end

          # Read a single bit
          #
          # @return [Integer] 0 or 1
          def read_bit
            unless @mode == :read
              raise ArgumentError,
                    "Can only read in read mode"
            end

            if @bits_in_buffer.zero?
              fill_buffer
            end

            @bits_in_buffer -= 1
            (@buffer >> @bits_in_buffer) & 1
          end

          # Write specified number of bits
          #
          # @param value [Integer] The value to write
          # @param count [Integer] Number of bits to write (1-32)
          # @return [void]
          def write_bits(value, count)
            unless @mode == :write
              raise ArgumentError,
                    "Can only write in write mode"
            end
            raise ArgumentError, "Count must be 1-32" unless count.between?(1,
                                                                            32)

            count.times do |i|
              bit = (value >> (count - 1 - i)) & 1
              write_bit(bit)
            end
          end

          # Write a single bit
          #
          # @param bit [Integer] 0 or 1
          # @return [void]
          def write_bit(bit)
            unless @mode == :write
              raise ArgumentError,
                    "Can only write in write mode"
            end

            @buffer = (@buffer << 1) | (bit & 1)
            @bits_in_buffer += 1

            flush_buffer if @bits_in_buffer == 8
          end

          # Align to byte boundary (read mode)
          #
          # @return [void]
          def align_to_byte
            return unless @mode == :read

            @bits_in_buffer = 0
            @buffer = 0
          end

          # Flush any remaining bits (write mode)
          #
          # @return [void]
          def flush
            return unless @mode == :write
            return if @bits_in_buffer.zero?

            # Pad with zeros to complete byte
            padding = 8 - @bits_in_buffer
            @buffer <<= padding
            @io.write([@buffer].pack("C"))
            @buffer = 0
            @bits_in_buffer = 0
          end

          # Check if at end of stream
          #
          # @return [Boolean] True if no more data available
          def eof?
            @mode == :read && @bits_in_buffer.zero? && @io.eof?
          end

          private

          # Fill buffer with next byte from stream
          #
          # @return [void]
          def fill_buffer
            byte = @io.read(1)
            raise EOFError, "Unexpected end of stream" if byte.nil?

            @buffer = byte.unpack1("C")
            @bits_in_buffer = 8
          end

          # Flush full buffer byte to stream
          #
          # @return [void]
          def flush_buffer
            @io.write([@buffer].pack("C"))
            @buffer = 0
            @bits_in_buffer = 0
          end
        end
      end
    end
  end
end
