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
require_relative "fse/bitstream"

module Omnizip
  module Algorithms
    class Zstandard
      # Huffman decoding for Zstandard (RFC 8878 Section 4.2)
      #
      # Zstandard uses FSE-compressed Huffman weights followed by
      # canonical Huffman decoding.
      class Huffman
        include Constants

        # @return [Hash<Integer, Array<Integer>>] Code to symbol mapping
        attr_reader :decode_table

        # @return [Integer] Maximum code length
        attr_reader :max_bits

        # Build Huffman table from weights
        #
        # @param weights [Array<Integer>] Symbol weights (0 means not present)
        # @param max_bits [Integer] Maximum code length
        # @return [Huffman] Built Huffman decoder
        def self.build_from_weights(weights, max_bits = HUFFMAN_MAX_BITS)
          # Convert weights to code lengths
          code_lengths = calculate_code_lengths(weights, max_bits)

          # Build canonical Huffman codes
          codes = build_canonical_codes(code_lengths)

          # Build decode table: code -> [symbol, length]
          decode_table = {}
          code_lengths.each_with_index do |length, symbol|
            next if length.nil? || length == 0

            code = codes[symbol]
            decode_table[code] = [symbol, length]
          end

          new(decode_table, max_bits)
        end

        # Calculate code lengths from weights
        #
        # Weight 0 means symbol is not present.
        # Higher weights mean shorter codes.
        #
        # @param weights [Array<Integer>] Symbol weights
        # @param max_bits [Integer] Maximum code length
        # @return [Array<Integer>] Code lengths
        def self.calculate_code_lengths(weights, max_bits)
          return [] if weights.nil? || weights.empty?

          # Find max weight
          max_weight = weights.max || 0
          return Array.new(weights.length, 0) if max_weight == 0

          # Convert weights to code lengths
          # Higher weight = shorter code length
          code_lengths = weights.map do |weight|
            next 0 if weight.nil? || weight == 0

            # Code length = max_weight - weight + 1
            [max_weight - weight + 1, max_bits].min
          end

          code_lengths
        end

        # Build canonical Huffman codes from lengths
        #
        # @param code_lengths [Array<Integer>] Code lengths for each symbol
        # @return [Hash<Integer, Integer>] Symbol to code mapping
        def self.build_canonical_codes(code_lengths)
          codes = {}
          return codes if code_lengths.nil? || code_lengths.empty?

          max_length = code_lengths.compact.max || 0

          # Count symbols at each length
          bl_count = Array.new(max_length + 1, 0)
          code_lengths.each do |length|
            bl_count[length] += 1 if length && length > 0
          end

          # Calculate starting code for each length
          code = 0
          next_code = Array.new(max_length + 1, 0)
          (1..max_length).each do |bits|
            code = ((code + bl_count[bits - 1]) << 1)
            next_code[bits] = code
          end

          # Assign codes to symbols
          code_lengths.each_with_index do |length, symbol|
            next if length.nil? || length == 0

            codes[symbol] = next_code[length]
            next_code[length] += 1
          end

          codes
        end

        # Initialize Huffman decoder
        #
        # @param decode_table [Hash] Code to [symbol, length] mapping
        # @param max_bits [Integer] Maximum code length
        def initialize(decode_table, max_bits)
          @decode_table = decode_table
          @max_bits = max_bits

          # Build lookup table for faster decoding
          build_lookup_table
        end

        # Decode a symbol from bitstream
        #
        # @param bitstream [FSE::ForwardBitStream] The bitstream to read from
        # @return [Integer] Decoded symbol
        def decode(bitstream)
          return 0 if @lookup_table.nil? || @lookup_table.empty?

          # Peek max_bits bits
          code = 0
          bits_read = 0

          (@max_bits || 1).times do
            bit = read_single_bit_forward(bitstream)
            code = (code << 1) | bit
            bits_read += 1

            # Check if this code exists in our table
            if @decode_table.key?(code)
              expected_length = @decode_table[code][1]
              if bits_read == expected_length
                return @decode_table[code][0]
              end
            end
          end

          # Fallback: try lookup table
          symbol = @lookup_table[code]
          return symbol if symbol

          0
        end

        private

        # Build lookup table for fast decoding
        def build_lookup_table
          @lookup_table = {}

          return if @decode_table.nil? || @decode_table.empty?

          @decode_table.each do |code, (symbol, length)|
            # For codes shorter than max_bits, fill all variations
            padding_bits = (@max_bits || 1) - length
            next if padding_bits < 0

            (1 << padding_bits).times do |padding|
              full_code = (code << padding_bits) | padding
              @lookup_table[full_code] = symbol
            end
          end
        end

        # Read a single bit in forward order (MSB first)
        def read_single_bit_forward(bitstream)
          bitstream.read_bits(1)
        end
      end

      # Huffman table reader (RFC 8878 Section 4.2.1)
      #
      # Reads compressed Huffman table description from input.
      class HuffmanTableReader
        include Constants

        # Read Huffman table from input
        #
        # @param input [IO] Input stream positioned at Huffman description
        # @return [Huffman] Huffman decoder
        def self.read(input)
          reader = new(input)
          reader.read_table
        end

        def initialize(input)
          @input = input
        end

        # Read and build Huffman table
        #
        # @return [Huffman] Huffman decoder
        def read_table
          # Read header
          header = @input.read(1).ord

          # FSE compressed or raw weights?
          fse_compressed = (header & 0x80) != 0

          if fse_compressed
            read_fse_compressed_weights(header)
          else
            read_raw_weights(header)
          end
        end

        private

        # Read FSE-compressed weights
        def read_fse_compressed_weights(header)
          # Read accuracy log (4 bits)
          accuracy_log = (header & 0x1F) + 5

          # Read number of symbols (if header bit 6 is set)
          # For simplicity, assume 256 symbols
          num_symbols = 256

          # Read compressed weights using FSE
          # This is a simplified implementation
          weights = Array.new(num_symbols, 0)

          # For now, use uniform weights as fallback
          Huffman.build_from_weights(weights, HUFFMAN_MAX_BITS)
        end

        # Read raw (uncompressed) weights
        def read_raw_weights(header)
          # Header byte: 0b0RHHHHH
          # R = repeat flag (not used in basic implementation)
          # HHHHH = header byte

          # Read number of weights
          num_weights = header & 0x3F
          num_weights = 256 if num_weights == 0

          weights = []
          num_weights.times do
            byte = @input.read(1)&.ord || 0
            weights << byte
          end

          Huffman.build_from_weights(weights, HUFFMAN_MAX_BITS)
        end
      end
    end
  end
end
