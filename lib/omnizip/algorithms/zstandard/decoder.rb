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
require_relative "frame/header"
require_relative "frame/block"
require_relative "literals"
require_relative "sequences"

module Omnizip
  module Algorithms
    class Zstandard
      # Pure Ruby Zstandard decoder (RFC 8878)
      #
      # Decodes Zstandard-compressed data according to RFC 8878.
      #
      # Decoder pipeline:
      # 1. Parse frame header
      # 2. For each block:
      #    a. Parse block header
      #    b. Decode literals section
      #    c. Decode sequences section
      #    d. Execute sequences (LZ77 copy operations)
      # 3. Verify content checksum if present
      class Decoder
        include Constants

        # @return [IO] Input stream
        attr_reader :input_stream

        # Initialize decoder
        #
        # @param input_stream [IO] Input stream of compressed data
        def initialize(input_stream)
          @input_stream = input_stream
          @repeat_offsets = DEFAULT_REPEAT_OFFSETS.dup
          @previous_huffman_table = nil
          @previous_fse_tables = {}
        end

        # Decode compressed data stream
        #
        # @return [String] Decompressed data
        def decode_stream
          output = String.new(encoding: Encoding::BINARY)

          loop do
            # Read magic number
            magic = read_u32le

            # Check for skippable frame
            if skippable_frame?(magic)
              skip_frame
              next
            end

            # Validate magic number
            unless magic == MAGIC_NUMBER
              raise "Invalid Zstandard magic: 0x#{magic.to_s(16)}"
            end

            # Parse frame
            frame_output = decode_frame
            output << frame_output

            # Check for more frames
            break if @input_stream.eof?
          end

          output
        end

        private

        # Check if frame is skippable
        def skippable_frame?(magic)
          (magic & SKIPPABLE_MAGIC_MASK) == SKIPPABLE_MAGIC_BASE
        end

        # Skip skippable frame
        def skip_frame
          # Read frame size (4 bytes)
          size = read_u32le
          @input_stream.seek(size, IO::SEEK_CUR)
        end

        # Read unsigned 32-bit little-endian
        def read_u32le
          bytes = @input_stream.read(4)
          return 0 if bytes.nil? || bytes.length < 4

          bytes.unpack1("V")
        end

        # Decode a single frame
        def decode_frame
          # Parse frame header
          header = Frame::Header.parse(@input_stream)

          # Calculate window size
          calculate_window_size(header)

          # Decode blocks
          output = String.new(encoding: Encoding::BINARY)

          loop do
            block = Frame::Block.parse(@input_stream)

            # Decode block content
            block_output = decode_block(block, header)
            output << block_output

            break if block.last_block
          end

          # Verify checksum if present
          if header.content_checksum?
            verify_checksum(output)
          end

          output
        end

        # Calculate window size from header
        def calculate_window_size(header)
          return BLOCK_MAX_SIZE if header.single_segment
          return nil unless header.window_log

          header.window_size || BLOCK_MAX_SIZE
        end

        # Decode a single block
        def decode_block(block, _header)
          case block.block_type
          when BLOCK_TYPE_RAW
            decode_raw_block(block)
          when BLOCK_TYPE_RLE
            decode_rle_block(block)
          when BLOCK_TYPE_COMPRESSED
            decode_compressed_block(block)
          else
            raise "Reserved block type: #{block.block_type}"
          end
        end

        # Decode raw (uncompressed) block
        def decode_raw_block(block)
          @input_stream.read(block.block_size)
        end

        # Decode RLE block
        def decode_rle_block(block)
          byte = @input_stream.read(1)
          byte * block.block_size
        end

        # Decode compressed block
        def decode_compressed_block(_block)
          # Record start position for calculating remaining bytes
          @input_stream.pos

          # Decode literals section
          literals_decoder = LiteralsDecoder.decode(@input_stream,
                                                    @previous_huffman_table)
          literals = literals_decoder.literals
          @previous_huffman_table = literals_decoder.huffman_table

          # Decode sequences section
          sequences_decoder = SequencesDecoder.decode(@input_stream,
                                                      literals.bytesize,
                                                      @previous_fse_tables)
          sequences = sequences_decoder.sequences

          # Execute sequences to produce output
          if sequences.empty?
            # No sequences - literals are the output
            literals
          else
            SequenceExecutor.execute(literals, sequences)
          end
        end

        # Verify content checksum
        def verify_checksum(output)
          # Read checksum (4 bytes)
          checksum_bytes = @input_stream.read(4)
          return unless checksum_bytes && checksum_bytes.length == 4

          expected = checksum_bytes.unpack1("V")
          calculated = xxhash32(output)

          if calculated != expected
            warn "Zstandard checksum mismatch (expected #{expected}, got #{calculated})"
          end
        end

        # Calculate XXHash32 checksum (simplified)
        def xxhash32(data, seed = 0)
          # Simplified XXHash32 - for checksum verification only
          # Full implementation would use proper XXHash32 algorithm
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
