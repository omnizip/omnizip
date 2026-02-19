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
      # BZip2 Encoder
      #
      # Orchestrates the full BZip2 compression pipeline:
      # 1. Block splitting (configurable block size)
      # 2. Burrows-Wheeler Transform (BWT)
      # 3. Move-to-Front Transform (MTF)
      # 4. Run-Length Encoding (RLE)
      # 5. Huffman Coding
      # 6. CRC32 checksum calculation
      #
      # Each block is compressed independently for better parallelization
      # potential and error recovery.
      class Encoder
        attr_reader :output, :block_size

        # Block size constants (in bytes)
        MIN_BLOCK_SIZE = 100_000  # 100KB
        MAX_BLOCK_SIZE = 900_000  # 900KB
        DEFAULT_BLOCK_SIZE = 900_000 # 900KB (level 9)

        # Initialize encoder
        #
        # @param output [IO] Output stream
        # @param options [Hash] Encoding options
        # @option options [Integer] :block_size Block size in bytes
        def initialize(output, options = {})
          @output = output
          @block_size = validate_block_size(
            options[:block_size] || DEFAULT_BLOCK_SIZE,
          )
          @bwt = Bwt.new
          @mtf = Mtf.new
          @rle = Rle.new
          @huffman = Huffman.new
        end

        # Encode stream using BZip2 algorithm
        #
        # @param input [String] Input data to encode
        # @return [void]
        def encode_stream(input)
          return if input.empty?

          # Split into blocks and encode each
          blocks = split_into_blocks(input)
          blocks.each { |block| encode_block(block) }
        end

        private

        # Validate and clamp block size to valid range
        #
        # @param size [Integer] Requested block size
        # @return [Integer] Validated block size
        def validate_block_size(size)
          size.clamp(MIN_BLOCK_SIZE, MAX_BLOCK_SIZE)
        end

        # Split input into blocks
        #
        # @param input [String] Input data
        # @return [Array<String>] Array of blocks
        def split_into_blocks(input)
          blocks = []
          offset = 0

          while offset < input.length
            block = input[offset, @block_size]
            blocks << block if block && !block.empty?
            offset += @block_size
          end

          blocks
        end

        # Encode single block through full pipeline
        #
        # @param block [String] Block data
        # @return [void]
        def encode_block(block)
          # Calculate CRC of original data
          crc = Checksums::Crc32.calculate(block)

          # Apply BWT
          bwt_data, primary_index = @bwt.encode(block)

          # Apply MTF
          mtf_data = @mtf.encode(bwt_data)

          # Apply RLE
          rle_data = @rle.encode(mtf_data)

          # Build frequency table for Huffman
          frequencies = build_frequency_table(rle_data)

          # Build Huffman tree and generate codes
          tree = @huffman.build_tree(frequencies)
          codes = generate_canonical_codes(tree)

          # Encode data with Huffman
          encoded_data = @huffman.encode(rle_data, codes)

          # Write block to output
          write_block(crc, primary_index, block.length, codes,
                      encoded_data, rle_data.length)
        end

        # Build frequency table from data
        #
        # @param data [String] Input data
        # @return [Hash<Integer, Integer>] Byte => frequency
        def build_frequency_table(data)
          freq = Hash.new(0)
          data.each_byte { |byte| freq[byte] += 1 }
          freq
        end

        # Generate canonical Huffman codes from tree
        #
        # @param tree [Huffman::Node] Huffman tree root
        # @return [Hash<Integer, String>] Symbol => canonical code
        def generate_canonical_codes(tree)
          # Get standard codes first
          standard_codes = @huffman.generate_codes(tree)

          # Convert to code lengths
          code_lengths = {}
          standard_codes.each do |symbol, code|
            code_lengths[symbol] = code.length
          end

          # Generate canonical codes from lengths
          # Sort by (length, symbol) to ensure deterministic ordering
          sorted_symbols = code_lengths.sort_by { |sym, len| [len, sym] }

          canonical_codes = {}
          code_value = 0
          prev_length = 0

          sorted_symbols.each do |symbol, length|
            # Shift code value for new length
            code_value <<= (length - prev_length)
            canonical_codes[symbol] = format("%0#{length}b", code_value)
            code_value += 1
            prev_length = length
          end

          canonical_codes
        end

        # Write encoded block to output
        #
        # @param crc [Integer] CRC32 of original block
        # @param primary_index [Integer] BWT primary index
        # @param original_length [Integer] Original block length
        # @param codes [Hash] Huffman codes
        # @param encoded_data [String] Huffman-encoded data
        # @param rle_length [Integer] Length after RLE
        # @return [void]
        def write_block(crc, primary_index, original_length, codes,
                        encoded_data, rle_length)
          write_block_header(crc, primary_index, original_length, rle_length)
          write_huffman_codes(codes)
          write_encoded_data(encoded_data)
        end

        # Write block header
        #
        # @param crc [Integer] CRC32 checksum
        # @param primary_index [Integer] BWT primary index
        # @param original_length [Integer] Original block length
        # @param rle_length [Integer] RLE length
        # @return [void]
        def write_block_header(crc, primary_index, original_length,
                               rle_length)
          @output.write([crc].pack("N"))
          @output.write([primary_index].pack("N"))
          @output.write([original_length].pack("N"))
          @output.write([rle_length].pack("N"))
        end

        # Write Huffman codes to output
        #
        # @param codes [Hash] Huffman codes
        # @return [void]
        def write_huffman_codes(codes)
          @output.write([codes.size].pack("n"))

          codes.each do |symbol, code|
            @output.write([symbol].pack("C"))
            @output.write([code.length].pack("C"))
          end
        end

        # Write encoded data to output
        #
        # @param encoded_data [String] Huffman-encoded data
        # @return [void]
        def write_encoded_data(encoded_data)
          @output.write([encoded_data.length].pack("N"))
          @output.write(encoded_data)
        end
      end
    end
  end
end
