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
        module LZ77Huffman
          # Sliding window buffer for LZ77 compression
          #
          # Provides a circular buffer that stores previously decoded bytes
          # for LZ77 match copying. The window allows looking back at
          # previously decoded data to resolve distance-length match pairs.
          #
          # Responsibilities:
          # - ONE responsibility: Window buffer management
          # - Store decoded bytes in circular buffer
          # - Copy matches from window offset
          # - Handle window wrap-around
          # - Efficient lookback for match resolution
          #
          # RAR LZ77 Window Sizes:
          # - RAR3: 32KB (32 * 1024 bytes)
          # - RAR4: 64KB (64 * 1024 bytes)
          # - RAR5: Up to 1GB (dynamic)
          class SlidingWindow
            # Default window size (64KB for RAR4)
            DEFAULT_SIZE = 64 * 1024

            # Initialize a new sliding window
            #
            # @param size [Integer] Window size in bytes
            def initialize(size = DEFAULT_SIZE)
              unless size.positive?
                raise ArgumentError,
                      "Window size must be positive"
              end

              @size = size
              @buffer = Array.new(size, 0)
              @position = 0
            end

            # Add a single byte to the window
            #
            # Stores the byte at the current position and advances.
            # When position reaches window size, it wraps around to 0.
            #
            # @param byte [Integer] Byte value (0-255)
            # @return [void]
            def add_byte(byte)
              raise ArgumentError, "Byte must be 0-255" unless byte.between?(0,
                                                                             255)

              @buffer[@position] = byte
              @position = (@position + 1) % @size
            end

            # Copy a match from the window
            #
            # Copies bytes from a backward offset (distance) and returns
            # them as an array. This is used to resolve LZ77 match pairs.
            #
            # The match can overlap with the current position (e.g., when
            # distance < length), which is handled byte-by-byte.
            #
            # @param distance [Integer] Backward offset (1 to window_size)
            # @param length [Integer] Number of bytes to copy (1+)
            # @return [Array<Integer>] Copied bytes
            def copy_match(distance, length)
              validate_match_params(distance, length)

              result = []
              start_pos = (@position - distance) % @size

              length.times do |i|
                copy_pos = (start_pos + i) % @size
                byte = @buffer[copy_pos]
                result << byte
                add_byte(byte) # Add to window as we copy
              end

              result
            end

            # Get current window position
            #
            # @return [Integer] Current position (0 to size-1)
            def position
              @position
            end

            # Get window size
            #
            # @return [Integer] Window size in bytes
            def size
              @size
            end

            # Get byte at specific offset from current position
            #
            # @param offset [Integer] Backward offset (1 to window_size)
            # @return [Integer] Byte value at offset
            def get_byte_at_offset(offset)
              unless offset.between?(
                1, @size
              )
                raise ArgumentError,
                      "Offset must be 1 to #{@size}"
              end

              pos = (@position - offset) % @size
              @buffer[pos]
            end

            # Reset window to initial state
            #
            # @return [void]
            def reset
              @buffer.fill(0)
              @position = 0
            end

            private

            # Validate match parameters
            #
            # @param distance [Integer] Distance parameter
            # @param length [Integer] Length parameter
            # @return [void]
            def validate_match_params(distance, length)
              unless distance.between?(1, @size)
                raise ArgumentError, "Distance must be 1 to #{@size}"
              end

              unless length.positive?
                raise ArgumentError,
                      "Length must be positive"
              end
            end
          end
        end
      end
    end
  end
end
