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

require_relative "bwt"
require_relative "mtf"
require_relative "rle"
require_relative "huffman"
require_relative "../../checksums/crc32"

module Omnizip
  module Algorithms
    class BZip2 < Algorithm
      # BZip2 Decoder
      #
      # Reverses the full BZip2 compression pipeline:
      # 1. Read block headers
      # 2. Decode Huffman coding
      # 3. Reverse Run-Length Encoding (RLE)
      # 4. Reverse Move-to-Front Transform (MTF)
      # 5. Reverse Burrows-Wheeler Transform (BWT)
      # 6. Verify CRC32 checksum
      #
      # Processes each block independently and concatenates results.
      class Decoder
        attr_reader :input

        # Initialize decoder
        #
        # @param input [IO] Input stream
        # @param options [Hash] Decoding options
        def initialize(input, _options = {})
          @input = input
          @bwt = Bwt.new
          @mtf = Mtf.new
          @rle = Rle.new
          @huffman = Huffman.new
        end

        # Decode stream using BZip2 algorithm
        #
        # @return [String] Decoded data
        def decode_stream
          result = []

          # Read and decode all blocks
          loop do
            block_data = decode_block
            break unless block_data

            result << block_data
          end

          result.join.b
        end

        private

        # Decode single block
        #
        # @return [String, nil] Decoded block or nil if no more blocks
        def decode_block
          # Read block header
          crc_bytes = @input.read(4)
          return nil unless crc_bytes && crc_bytes.length == 4

          expected_crc = crc_bytes.unpack1("N")
          primary_index = @input.read(4).unpack1("N")
          @input.read(4).unpack1("N")
          rle_length = @input.read(4).unpack1("N")

          # Read Huffman code table
          codes = read_huffman_codes

          # Read encoded data
          encoded_length = @input.read(4).unpack1("N")
          encoded_data = @input.read(encoded_length)

          # Rebuild Huffman tree from codes
          tree = rebuild_huffman_tree(codes)

          # Decode Huffman
          rle_data = @huffman.decode(encoded_data, tree, rle_length)

          # Reverse RLE
          mtf_data = @rle.decode(rle_data)

          # Reverse MTF
          bwt_data = @mtf.decode(mtf_data)

          # Reverse BWT
          original_data = @bwt.decode(bwt_data, primary_index)

          # Verify CRC
          actual_crc = Checksums::Crc32.calculate(original_data)
          if actual_crc != expected_crc
            raise "CRC mismatch: expected #{expected_crc}, " \
                  "got #{actual_crc}"
          end

          original_data
        end

        # Read Huffman code table from stream
        #
        # @return [Hash<Integer, String>] Symbol => binary code
        def read_huffman_codes
          codes = {}
          code_count = @input.read(2).unpack1("n")

          code_count.times do
            symbol = @input.read(1).unpack1("C")
            code_length = @input.read(1).unpack1("C")
            codes[symbol] = code_length
          end

          codes
        end

        # Rebuild Huffman tree from code lengths
        #
        # Creates canonical Huffman codes and builds tree
        #
        # @param code_lengths [Hash<Integer, Integer>] Symbol => length
        # @return [Huffman::Node] Root of Huffman tree
        def rebuild_huffman_tree(code_lengths)
          # Sort symbols by code length, then by symbol value
          sorted_symbols = code_lengths.sort_by { |sym, len| [len, sym] }

          # Generate canonical codes
          codes = {}
          code_value = 0
          prev_length = 0

          sorted_symbols.each do |symbol, length|
            # Shift code value for new length
            code_value <<= (length - prev_length)
            codes[symbol] = format("%0#{length}b", code_value)
            code_value += 1
            prev_length = length
          end

          # Build tree from codes
          build_tree_from_codes(codes)
        end

        # Build Huffman tree from code strings
        #
        # @param codes [Hash<Integer, String>] Symbol => binary code
        # @return [Huffman::Node] Root node
        def build_tree_from_codes(codes)
          root = Huffman::Node.new(nil, 0)

          codes.each do |symbol, code|
            current = root

            code.each_char do |bit|
              if bit == "0"
                current.left ||= Huffman::Node.new(nil, 0)
                current = current.left
              else
                current.right ||= Huffman::Node.new(nil, 0)
                current = current.right
              end
            end

            current.symbol = symbol
          end

          root
        end
      end
    end
  end
end
