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
    class BZip2 < Algorithm
      # Huffman Coding for BZip2
      #
      # Implements canonical Huffman coding for the final compression
      # stage of BZip2. Huffman coding assigns variable-length codes
      # to symbols based on their frequencies, with more frequent
      # symbols getting shorter codes.
      #
      # This implementation:
      # 1. Builds a Huffman tree from symbol frequencies
      # 2. Generates canonical codes for efficient decoding
      # 3. Encodes data as a bit stream
      # 4. Decodes bit streams back to symbols
      class Huffman
        # Huffman tree node
        class Node
          attr_accessor :symbol, :frequency, :left, :right

          # Initialize node
          #
          # @param symbol [Integer, nil] Symbol (nil for internal nodes)
          # @param frequency [Integer] Frequency/weight
          def initialize(symbol, frequency)
            @symbol = symbol
            @frequency = frequency
            @left = nil
            @right = nil
          end

          # Check if node is a leaf
          #
          # @return [Boolean] True if leaf node
          def leaf?
            @left.nil? && @right.nil?
          end
        end

        # Build Huffman tree from frequency table
        #
        # @param frequencies [Hash<Integer, Integer>] Symbol => frequency
        # @return [Node, nil] Root node of Huffman tree
        def build_tree(frequencies)
          return nil if frequencies.empty?

          # Create leaf nodes
          nodes = frequencies.map do |symbol, freq|
            Node.new(symbol, freq)
          end

          # Build tree bottom-up
          while nodes.length > 1
            # Sort by frequency
            nodes.sort_by!(&:frequency)

            # Take two lowest frequency nodes
            left = nodes.shift
            right = nodes.shift

            # Create parent node
            parent = Node.new(nil, left.frequency + right.frequency)
            parent.left = left
            parent.right = right

            # Add back to nodes
            nodes << parent
          end

          nodes.first
        end

        # Generate code table from Huffman tree
        #
        # @param root [Node] Root of Huffman tree
        # @return [Hash<Integer, String>] Symbol => binary code
        def generate_codes(root)
          return {} if root.nil?

          codes = {}
          generate_codes_recursive(root, "", codes)
          codes
        end

        # Encode data using Huffman codes
        #
        # @param data [String] Input data to encode
        # @param codes [Hash<Integer, String>] Symbol => binary code
        # @return [String] Encoded bit stream (as binary string)
        def encode(data, codes)
          return "".b if data.empty?

          bits = []

          data.each_byte do |byte|
            code = codes[byte]
            raise "No code for byte #{byte}" unless code

            bits << code
          end

          bits_to_bytes(bits.join)
        end

        # Decode bit stream using Huffman tree
        #
        # @param bits [String] Encoded bit stream
        # @param root [Node] Root of Huffman tree
        # @param length [Integer] Expected output length
        # @return [String] Decoded data
        def decode(bits, root, length)
          return "".b if bits.empty? || root.nil?

          result = []
          current = root
          bit_string = bytes_to_bits(bits)
          bit_index = 0

          while result.length < length && bit_index < bit_string.length
            bit = bit_string[bit_index]
            bit_index += 1

            # Navigate tree
            current = (bit == "0" ? current.left : current.right)

            # Check if we reached a leaf
            if current.leaf?
              result << current.symbol
              current = root
            end
          end

          result.pack("C*")
        end

        private

        # Recursively generate codes for all symbols
        #
        # @param node [Node] Current node
        # @param code [String] Current code path
        # @param codes [Hash] Code table being built
        # @return [void]
        def generate_codes_recursive(node, code, codes)
          return if node.nil?

          if node.leaf?
            codes[node.symbol] = code.empty? ? "0" : code
          else
            generate_codes_recursive(node.left, "#{code}0", codes)
            generate_codes_recursive(node.right, "#{code}1", codes)
          end
        end

        # Convert bit string to bytes
        #
        # @param bits [String] Bit string (e.g., "10110101")
        # @return [String] Byte string
        def bits_to_bytes(bits)
          # Pad to multiple of 8
          padding = (8 - (bits.length % 8)) % 8
          bits += ("0" * padding)

          # Convert to bytes
          bytes = []
          (0...bits.length).step(8) do |i|
            byte_bits = bits[i, 8]
            bytes << byte_bits.to_i(2)
          end

          bytes.pack("C*")
        end

        # Convert bytes to bit string
        #
        # @param bytes [String] Byte string
        # @return [String] Bit string
        def bytes_to_bits(bytes)
          bytes.bytes.map { |b| format("%08b", b) }.join
        end
      end
    end
  end
end
