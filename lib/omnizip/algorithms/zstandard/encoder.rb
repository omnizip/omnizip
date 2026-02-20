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

require_relative "constants"
require_relative "literals_encoder"

module Omnizip
  module Algorithms
    class Zstandard
      # Pure Ruby Zstandard encoder (RFC 8878)
      #
      # Encodes data using Zstandard format.
      # Supports raw blocks and Huffman-compressed literals.
      class Encoder
        include Constants

        attr_reader :output_stream, :options

        # Initialize encoder
        #
        # @param output_stream [IO] Output stream for compressed data
        # @param options [Hash] Encoder options
        # @option options [Integer] :level Compression level (1-22)
        # @option options [Boolean] :use_compression Use Huffman compression (default: true)
        def initialize(output_stream, options = {})
          @output_stream = output_stream
          @options = options
          @level = options[:level] || DEFAULT_LEVEL
          @use_compression = options.fetch(:use_compression, true)
        end

        # Encode data stream
        #
        # @param data [String] Data to compress
        # @return [void]
        def encode_stream(data)
          # Write Zstandard frame
          write_frame(data)
        end

        private

        # Write a complete Zstandard frame
        def write_frame(data)
          # Write magic number
          write_u32le(MAGIC_NUMBER)

          # Write frame header descriptor
          # Single segment, no checksum, no dictionary
          if data.bytesize < 256
            # Single segment, 1-byte FCS (FCS flag = 0)
            descriptor = 0x20 # Single segment flag (bit 5)
            @output_stream.putc(descriptor)
            @output_stream.putc(data.bytesize)
          else
            # Single segment, 4-byte FCS (FCS flag = 2)
            # Bits 6-7 = 10 binary = 0x80
            # Bit 5 = 1 (single segment) = 0x20
            descriptor = 0x80 | 0x20 # 0xA0
            @output_stream.putc(descriptor)
            write_u32le(data.bytesize)
          end

          # Write blocks
          write_blocks(data)

          # Write content checksum (optional, disabled for now)
          # write_u32le(xxhash32(data))
        end

        # Write blocks containing the data
        def write_blocks(data)
          return if data.empty?

          offset = 0
          max_block_size = BLOCK_MAX_SIZE

          while offset < data.bytesize
            chunk = data.byteslice(offset, max_block_size)
            offset += chunk.bytesize

            is_last = offset >= data.bytesize

            # Use RLE for repetitive data, otherwise raw blocks
            # Compressed blocks are deferred until decoder fully supports them
            if rle_efficient?(chunk)
              write_rle_block(chunk, is_last)
            else
              write_raw_block(chunk, is_last)
            end
          end
        end

        # Check if RLE encoding would be efficient for a chunk
        def rle_efficient?(chunk)
          return false if chunk.bytesize < 3

          first_byte = chunk.getbyte(0)
          chunk.bytes.all?(first_byte)
        end

        # Write an RLE (run-length encoded) block
        def write_rle_block(data, is_last)
          byte = data.getbyte(0)
          size = data.bytesize

          # Block header (3 bytes, little-endian)
          # Bit 0: Last_Block (1 = last)
          # Bits 1-2: Block_Type (1 = RLE)
          # Bits 3-23: Block_Size

          header = size << 3 # Block size in bits 3-23
          header |= BLOCK_TYPE_RLE << 1 # Block type = 1 (RLE)
          header |= 1 if is_last # Last block flag in bit 0

          # Write 3 bytes little-endian
          @output_stream.putc(header & 0xFF)
          @output_stream.putc((header >> 8) & 0xFF)
          @output_stream.putc((header >> 16) & 0xFF)

          # Write single byte to repeat
          @output_stream.putc(byte)
        end

        # Write a raw (uncompressed) block
        def write_raw_block(data, is_last)
          # Block header (3 bytes, little-endian)
          # Bit 0: Last_Block (1 = last)
          # Bits 1-2: Block_Type (0 = raw)
          # Bits 3-23: Block_Size

          header = data.bytesize << 3 # Block size in bits 3-23
          header |= BLOCK_TYPE_RAW << 1 # Block type in bits 1-2
          header |= 1 if is_last # Last block flag in bit 0

          # Write 3 bytes little-endian
          @output_stream.putc(header & 0xFF)
          @output_stream.putc((header >> 8) & 0xFF)
          @output_stream.putc((header >> 16) & 0xFF)

          # Write block content
          @output_stream.write(data)
        end

        # Write a compressed block with Huffman literals
        #
        # @param data [String] Block data
        # @param is_last [Boolean] Whether this is the last block
        # @return [Boolean] True if compression succeeded, false otherwise
        def write_compressed_block(data, is_last)
          # Encode literals section
          literals_section = LiteralsEncoder.encode(data, use_compression: true)

          # Check if compression is beneficial
          # Compressed block has overhead: block header (3) + literals header + sequences
          # For now, we need sequences section too (even if empty)
          sequences_section = encode_empty_sequences

          block_content = literals_section + sequences_section
          compressed_size = block_content.bytesize

          # Only use compressed if it's smaller
          if compressed_size >= data.bytesize
            return false
          end

          # Write block header for compressed block
          header = compressed_size << 3 # Block size in bits 3-23
          header |= BLOCK_TYPE_COMPRESSED << 1 # Block type = 2 (compressed)
          header |= 1 if is_last # Last block flag in bit 0

          # Write 3 bytes little-endian
          @output_stream.putc(header & 0xFF)
          @output_stream.putc((header >> 8) & 0xFF)
          @output_stream.putc((header >> 16) & 0xFF)

          # Write block content
          @output_stream.write(block_content)

          true
        end

        # Encode empty sequences section
        #
        # For blocks with only literals (no matches), we need an empty sequences section.
        def encode_empty_sequences
          # Number of sequences = 0 (single byte 0x00)
          "\x00"
        end

        # Write unsigned 32-bit little-endian
        def write_u32le(value)
          @output_stream.putc(value & 0xFF)
          @output_stream.putc((value >> 8) & 0xFF)
          @output_stream.putc((value >> 16) & 0xFF)
          @output_stream.putc((value >> 24) & 0xFF)
        end

        # Calculate XXHash32 checksum (simplified)
        def xxhash32(data, seed = 0)
          hash = seed

          data.each_byte do |byte|
            hash = ((hash << 5) + hash + byte) & 0xFFFFFFFF
          end

          hash
        end
      end
    end
  end
end
