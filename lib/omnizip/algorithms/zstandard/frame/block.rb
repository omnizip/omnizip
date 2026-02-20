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

require_relative "../constants"

module Omnizip
  module Algorithms
    class Zstandard
      module Frame
        # Zstandard block header parser (RFC 8878 Section 3.1.1.2)
        #
        # Block_Header structure (3 bytes, little-endian):
        # - Last_Block: bit 0
        # - Block_Type: bits 1-2
        # - Block_Size: bits 3-23
        class Block
          include Constants

          # @return [Boolean] True if this is the last block
          attr_reader :last_block

          # @return [Integer] Block type (0=Raw, 1=RLE, 2=Compressed, 3=Reserved)
          attr_reader :block_type

          # @return [Integer] Block size in bytes
          attr_reader :block_size

          # @return [Integer] Block header bytes
          attr_reader :raw_header

          # Parse block header from input
          #
          # @param input [IO] Input stream positioned at block header
          # @return [Block] Parsed block header
          def self.parse(input)
            bytes = input.read(3)
            # Read 3 bytes as little-endian 24-bit value
            raw = bytes.nil? ? 0 : (bytes.getbyte(0) | (bytes.getbyte(1) << 8) | (bytes.getbyte(2) << 16))
            last_block = raw.allbits?(0x01)
            block_type = (raw >> 1) & 0x03
            block_size = (raw >> 3) & 0x1FFFFF

            new(last_block, block_type, block_size, raw)
          end

          # Initialize with parsed values
          #
          # @param last_block [Boolean]
          # @param block_type [Integer]
          # @param block_size [Integer]
          # @param raw_header [Integer]
          def initialize(last_block, block_type, block_size, raw_header)
            @last_block = last_block
            @block_type = block_type
            @block_size = block_size
            @raw_header = raw_header
          end

          # Check if this is a raw (uncompressed) block
          #
          # @return [Boolean]
          def raw?
            @block_type == BLOCK_TYPE_RAW
          end

          # Check if this is an RLE block
          #
          # @return [Boolean]
          def rle?
            @block_type == BLOCK_TYPE_RLE
          end

          # Check if this is a compressed block
          #
          # @return [Boolean]
          def compressed?
            @block_type == BLOCK_TYPE_COMPRESSED
          end

          # Check if block type is reserved
          #
          # @return [Boolean]
          def reserved?
            @block_type == BLOCK_TYPE_RESERVED
          end

          # Validate block type
          #
          # @return [Boolean] True if block type is valid
          def valid?
            !reserved?
          end

          # Get block type name
          #
          # @return [Symbol]
          def type_name
            case @block_type
            when BLOCK_TYPE_RAW then :raw
            when BLOCK_TYPE_RLE then :rle
            when BLOCK_TYPE_COMPRESSED then :compressed
            when BLOCK_TYPE_RESERVED then :reserved
            end
          end
        end
      end
    end
  end
end
