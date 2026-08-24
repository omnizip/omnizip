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
      # Pure Ruby Zstandard encoder (RFC 8878).
      #
      # Emits a single-segment frame. Each 128 KiB chunk of input
      # becomes one block, choosing whichever is smallest: RLE, a
      # Compressed_Block (Huffman-coded literals + an empty sequences
      # section), or a Raw_Block fallback for incompressible data.
      class Encoder
        include Constants

        attr_reader :output_stream, :options

        # Initialize encoder
        #
        # @param output_stream [IO] output for compressed data
        # @param options [Hash]
        # @option options [Integer] :level compression level (1-22)
        # @option options [Boolean] :checksum write the frame checksum
        def initialize(output_stream, options = {})
          @output_stream = output_stream
          @options = options
          @level = options[:level] || DEFAULT_LEVEL
          @checksum = options.fetch(:checksum, false)
        end

        # Encode a data stream
        #
        # @param data [String]
        def encode_stream(data)
          data = data.dup.force_encoding(Encoding::BINARY)
          write_frame(data)
        end

        private

        def write_frame(data)
          write_u32le(MAGIC_NUMBER)
          write_frame_header(data)
          write_blocks(data)
          write_u32le(XXHash64.frame_checksum(data)) if @checksum
        end

        # Single-segment frame header: no window descriptor, no
        # dictionary; Frame_Content_Size in 1, 2, 4 or 8 bytes.
        def write_frame_header(data)
          size = data.bytesize
          if size < 256
            @output_stream.putc(0x20) # single segment, FCS 1 byte
            @output_stream.putc(size)
          elsif size <= 65_791
            @output_stream.putc(0x60) # single segment, FCS 2 bytes (+256)
            write_u16le(size - 256)
          elsif size <= 0xFFFFFFFF
            @output_stream.putc(0xA0) # single segment, FCS 4 bytes
            write_u32le(size)
          else
            @output_stream.putc(0xE0) # single segment, FCS 8 bytes
            write_u64le(size)
          end
        end

        def write_blocks(data)
          return write_empty_last_block if data.empty?

          offset = 0
          while offset < data.bytesize
            chunk = data.byteslice(offset, BLOCK_MAX_SIZE)
            offset += chunk.bytesize
            is_last = offset >= data.bytesize
            write_chunk(chunk, is_last)
          end
        end

        def write_empty_last_block
          write_block_header(1, BLOCK_TYPE_RAW, 0)
        end

        def write_chunk(chunk, is_last)
          if chunk.bytesize >= 4 && rle_chunk?(chunk)
            write_block_header(is_last ? 1 : 0, BLOCK_TYPE_RLE, chunk.bytesize)
            @output_stream.putc(chunk.getbyte(0))
            return
          end

          content = try_compressed(chunk)
          if content.nil?
            write_block_header(is_last ? 1 : 0, BLOCK_TYPE_RAW,
                               chunk.bytesize)
            @output_stream.write(chunk)
          else
            write_block_header(is_last ? 1 : 0, BLOCK_TYPE_COMPRESSED,
                               content.bytesize)
            @output_stream.write(content)
          end
        end

        # Build a Compressed_Block content: literals section plus an
        # empty sequences section (nbSeq = 0). Returns nil when the
        # result is not smaller than the raw chunk.
        def try_compressed(chunk)
          literals_section = LiteralsEncoder.encode(chunk)
          # A single 0x00 byte: Number_of_Sequences = 0.
          content = literals_section + "\x00".b
          return nil if content.bytesize >= chunk.bytesize

          content
        rescue Omnizip::CompressionError
          nil
        end

        def rle_chunk?(chunk)
          first = chunk.getbyte(0)
          idx = 1
          while idx < chunk.bytesize
            return false if chunk.getbyte(idx) != first

            idx += 1
          end
          true
        end

        def write_block_header(last, type, size)
          header = (last & 1) | (type << 1) | (size << 3)
          @output_stream.putc(header & 0xFF)
          @output_stream.putc((header >> 8) & 0xFF)
          @output_stream.putc((header >> 16) & 0xFF)
        end

        def write_u16le(value)
          @output_stream.putc(value & 0xFF)
          @output_stream.putc((value >> 8) & 0xFF)
        end

        def write_u32le(value)
          @output_stream.putc(value & 0xFF)
          @output_stream.putc((value >> 8) & 0xFF)
          @output_stream.putc((value >> 16) & 0xFF)
          @output_stream.putc((value >> 24) & 0xFF)
        end

        def write_u64le(value)
          8.times { |i| @output_stream.putc((value >> (8 * i)) & 0xFF) }
        end
      end
    end
  end
end
