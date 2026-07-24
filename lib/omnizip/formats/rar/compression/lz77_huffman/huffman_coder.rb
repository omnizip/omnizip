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
          # Huffman coding for RAR LZ77+Huffman compression
          #
          # Implements canonical Huffman tree decoding for RAR archives.
          # RAR uses multiple Huffman tables:
          # - MC (Main Code): Literals and length codes
          # - LD (Length-Distance): Distance codes
          # - RC (Repeat Count): Run-length encoding
          # - LDD (Low Distance): Low distance values
          #
          # Responsibilities:
          # - ONE responsibility: Huffman tree operations
          # - Build canonical Huffman trees from code lengths
          # - Decode symbols using Huffman trees
          # - Parse tree structure from bit stream
          #
          # Canonical Huffman Code Properties:
          # - Codes of same length are sequential
          # - Shorter codes have lower values
          # - Deterministic tree construction from lengths
          class HuffmanCoder
            # Maximum code length for RAR
            MAX_CODE_LENGTH = 15

            # Initialize Huffman coder
            def initialize
              @decode_table = {}
              @code_lengths = []
            end

            # Build Huffman tree from code lengths
            #
            # Constructs a canonical Huffman tree given the code lengths
            # for each symbol. This is how RAR transmits Huffman tables.
            #
            # @param code_lengths [Array<Integer>] Code length for each symbol
            # @return [void]
            def build_tree(code_lengths)
              @code_lengths = code_lengths
              @decode_table = {}

              # Count codes of each length
              length_counts = Array.new(MAX_CODE_LENGTH + 1, 0)
              code_lengths.each do |len|
                length_counts[len] += 1 if len.positive?
              end

              # Calculate first code for each length
              first_codes = Array.new(MAX_CODE_LENGTH + 1, 0)
              code = 0
              (1..MAX_CODE_LENGTH).each do |len|
                first_codes[len] = code
                code = (code + length_counts[len]) << 1
              end

              # Assign codes to symbols
              code_lengths.each_with_index do |len, symbol|
                next if len.zero?

                code = first_codes[len]
                first_codes[len] += 1

                # Store in decode table: [code, length] => symbol
                key = (code << 8) | len
                @decode_table[key] = symbol
              end
            end

            # Decode a single symbol from bit stream
            #
            # Reads bits one at a time until a valid Huffman code is found,
            # then returns the corresponding symbol.
            #
            # @param bit_stream [BitStream] Input bit stream
            # @return [Integer, nil] Decoded symbol or nil if end
            def decode_symbol(bit_stream)
              code = 0
              length = 0

              # Read bits until we find a valid code
              (1..MAX_CODE_LENGTH).each do |len|
                bit = bit_stream.read_bit
                code = (code << 1) | bit
                length = len

                # Check if this code exists in decode table
                key = (code << 8) | length
                return @decode_table[key] if @decode_table.key?(key)
              end

              # No valid code found
              nil
            end

            # Parse Huffman tree from RAR bit stream
            #
            # RAR encodes Huffman trees in a compact format:
            # 1. Number of code lengths
            # 2. Code lengths (potentially compressed)
            # 3. Tree structure
            #
            # This is a simplified implementation for MVP.
            #
            # @param bit_stream [BitStream] Input bit stream
            # @param num_symbols [Integer] Number of symbols in alphabet
            # @return [void]
            def parse_tree(bit_stream, num_symbols)
              code_lengths = Array.new(num_symbols, 0)

              # Read code lengths (simplified - real RAR uses RLE)
              num_symbols.times do |i|
                # Read length as 4-bit value
                len = bit_stream.read_bits(4)
                code_lengths[i] = len
              end

              build_tree(code_lengths)
            end

            # Check if tree is empty
            #
            # @return [Boolean] True if no codes defined
            def empty?
              @decode_table.empty?
            end

            # Get number of symbols in tree
            #
            # @return [Integer] Number of symbols
            def symbol_count
              @decode_table.size
            end

            # Reset the coder
            #
            # @return [void]
            def reset
              @decode_table = {}
              @code_lengths = []
            end

            # Encode a symbol (for future encoder implementation)
            #
            # @param symbol [Integer] Symbol to encode
            # @return [Array<Integer, Integer>] [code, length]
            def encode_symbol(symbol)
              # Find code for symbol
              @decode_table.each do |key, sym|
                next unless sym == symbol

                code = key >> 8
                length = key & 0xFF
                return [code, length]
              end

              nil
            end
          end
        end
      end
    end
  end
end
