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
      # Pure Ruby Zstandard decoder (RFC 8878).
      #
      # Pipeline:
      #
      # 1. For each frame: parse the frame header and reset per-frame
      #    state (repeat offsets, previous Huffman table, previous FSE
      #    tables).
      # 2. For each block: parse the 3-byte block header and dispatch on
      #    the block type (raw copy, RLE expansion, or compressed =
      #    literals + sequences).
      # 3. Verify the optional content checksum: the low 32 bits of
      #    XXHash64 over the decoded frame content.
      class Decoder
        include Constants

        # @return [IO] input stream
        attr_reader :input_stream

        def initialize(input_stream)
          @input_stream = input_stream
          @executor = SequenceExecutor.new
          @previous_huffman_table = nil
          @previous_fse_tables = {}
        end

        # Decode a complete stream (one or more concatenated frames).
        #
        # @return [String] decompressed data (binary)
        def decode_stream
          data = read_all
          output = String.new(encoding: Encoding::BINARY)
          pos = 0

          loop do
            remaining = data.bytesize - pos
            break if remaining.zero?
            raise Omnizip::DecompressionError, "trailing bytes are not a frame" if remaining < 4

            magic = data.byteslice(pos, 4).unpack1("V")

            if (magic & SKIPPABLE_MAGIC_MASK) == SKIPPABLE_MAGIC_BASE
              pos = skip_skippable_frame(data, pos)
              next
            end
            unless magic == MAGIC_NUMBER
              raise Omnizip::DecompressionError,
                    "invalid Zstandard magic: 0x#{magic.to_s(16)}"
            end

            frame_output, pos = decode_frame(data, pos + 4)
            output << frame_output
          end

          output
        end

        private

        def read_all
          data = @input_stream.read
          data ||= ""
          data.dup.force_encoding(Encoding::BINARY)
        end

        def skip_skippable_frame(data, pos)
          raise Omnizip::DecompressionError, "truncated skippable frame" if data.bytesize < pos + 8

          size = data.byteslice(pos + 4, 4).unpack1("V")
          end_pos = pos + 8 + size
          if data.bytesize < end_pos
            raise Omnizip::DecompressionError, "truncated skippable frame body"
          end

          end_pos
        end

        # Decode one frame (input positioned after the magic).
        # Returns [frame_output, pos_after_frame].
        def decode_frame(data, pos)
          header, pos = Frame::Header.parse_from(data, pos)

          # Reset per-frame state: repeat offsets, previous Huffman
          # table, previous FSE tables.
          @executor = SequenceExecutor.new
          @previous_huffman_table = nil
          @previous_fse_tables = {}

          output = String.new(encoding: Encoding::BINARY)
          loop do
            block, pos = Frame::Block.parse_from(data, pos)
            if block.reserved?
              raise Omnizip::DecompressionError,
                    "reserved block type in frame"
            end

            pos = decode_block(block, data, pos, output)
            break if block.last_block
          end

          if header.content_checksum?
            if data.bytesize < pos + 4
              raise Omnizip::DecompressionError, "truncated frame checksum"
            end

            expected = data.byteslice(pos, 4).unpack1("V")
            actual = XXHash64.frame_checksum(output)
            if expected != actual
              raise Omnizip::DecompressionError,
                    "frame checksum mismatch: stored 0x#{expected.to_s(16)}, " \
                    "computed 0x#{actual.to_s(16)}"
            end
            pos += 4
          end

          [output, pos]
        end

        def decode_block(block, data, pos, output)
          case block.block_type
          when BLOCK_TYPE_RAW
            if data.bytesize < pos + block.block_size
              raise Omnizip::DecompressionError, "truncated raw block"
            end

            output << data.byteslice(pos, block.block_size)
            pos + block.block_size
          when BLOCK_TYPE_RLE
            raise Omnizip::DecompressionError, "truncated RLE block" if data.bytesize < pos + 1

            output << (data.getbyte(pos).chr * block.block_size)
            pos + 1
          when BLOCK_TYPE_COMPRESSED
            block_end = pos + block.block_size
            if data.bytesize < block_end
              raise Omnizip::DecompressionError, "truncated compressed block"
            end

            decode_compressed_block(data.byteslice(pos...block_end), output)
            block_end
          end
        end

        def decode_compressed_block(block_input, output)
          literals_decoder = LiteralsDecoder.decode(block_input,
                                                    @previous_huffman_table)
          @previous_huffman_table = literals_decoder.huffman_table ||
            @previous_huffman_table

          sequences_decoder = SequencesDecoder.decode(
            block_input.byteslice(literals_decoder.consumed..),
            @previous_fse_tables,
            @executor,
          )
          # Merge: Repeat-mode tables are not re-emitted, so the entries
          # carried from earlier blocks must survive.
          @previous_fse_tables =
            @previous_fse_tables.merge(sequences_decoder.fse_tables)

          @executor.execute(literals_decoder.literals,
                            sequences_decoder.sequences, output)
        end
      end
    end
  end
end
