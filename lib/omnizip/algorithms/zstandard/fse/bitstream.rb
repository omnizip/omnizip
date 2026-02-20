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
        # FSE bitstream reader (RFC 8878 Section 4.1)
        #
        # Reads FSE-encoded bitstreams which are read in reverse order
        # (from end to beginning) according to RFC 8878.
        #
        # The bitstream is consumed from the end toward the beginning,
        # with bits read from LSB to MSB within each byte.
        class BitStream
          # @return [String] The compressed data
          attr_reader :data

          # @return [Integer] Current bit position (from end)
          attr_reader :bit_position

          # Initialize bitstream with data
          #
          # @param data [String] The compressed bitstream data
          def initialize(data)
            @data = data.dup.force_encoding(Encoding::BINARY)
            @bit_position = data.bytesize * 8
          end

          # Read bits from the stream (in reverse order)
          #
          # Bits are read from LSB to MSB, starting from the end of the stream.
          #
          # @param count [Integer] Number of bits to read
          # @return [Integer] The read bits
          def read_bits(count)
            return 0 if count.zero?

            result = 0
            count.times do |i|
              bit = read_single_bit
              result |= (bit << i)
            end
            result
          end

          # Peek at bits without consuming them
          #
          # @param count [Integer] Number of bits to peek
          # @return [Integer] The peeked bits
          def peek_bits(count)
            saved_position = @bit_position
            result = read_bits(count)
            @bit_position = saved_position
            result
          end

          # Check if bitstream is exhausted
          #
          # @return [Boolean]
          def exhausted?
            @bit_position <= 0
          end

          # Get remaining bits
          #
          # @return [Integer]
          def remaining_bits
            @bit_position
          end

          # Align to byte boundary (skip remaining bits in current byte)
          def align_to_byte
            @bit_position = ((@bit_position + 7) / 8) * 8
          end

          private

          # Read a single bit from the stream
          #
          # @return [Integer] 0 or 1
          def read_single_bit
            return 0 if @bit_position <= 0

            @bit_position -= 1
            byte_index = @bit_position / 8
            bit_index = @bit_position % 8

            return 0 if byte_index.negative? || byte_index >= @data.bytesize

            byte = @data.getbyte(byte_index)
            (byte >> bit_index) & 1
          end
        end

        # Forward bitstream reader (for Huffman decoding)
        #
        # Reads bits in normal forward order from a starting position.
        class ForwardBitStream
          # @return [String] The compressed data
          attr_reader :data

          # @return [Integer] Current bit position
          attr_reader :bit_position

          # Initialize bitstream with data
          #
          # @param data [String] The compressed bitstream data
          # @param start_byte [Integer] Starting byte position
          def initialize(data, start_byte = 0)
            @data = data.dup.force_encoding(Encoding::BINARY)
            @bit_position = start_byte * 8
          end

          # Read bits from the stream (in forward order)
          #
          # Bits are read from MSB to LSB within each byte.
          #
          # @param count [Integer] Number of bits to read
          # @return [Integer] The read bits
          def read_bits(count)
            return 0 if count.zero?

            result = 0
            count.times do
              result = (result << 1) | read_single_bit
            end
            result
          end

          # Check if bitstream is exhausted
          #
          # @return [Boolean]
          def exhausted?
            @bit_position >= @data.bytesize * 8
          end

          # Get current byte position
          #
          # @return [Integer]
          def byte_position
            @bit_position / 8
          end

          private

          # Read a single bit from the stream
          #
          # @return [Integer] 0 or 1
          def read_single_bit
            return 0 if exhausted?

            byte_index = @bit_position / 8
            bit_index = 7 - (@bit_position % 8) # MSB first

            @bit_position += 1

            return 0 if byte_index >= @data.bytesize

            byte = @data.getbyte(byte_index)
            (byte >> bit_index) & 1
          end
        end
      end
    end
  end
end
