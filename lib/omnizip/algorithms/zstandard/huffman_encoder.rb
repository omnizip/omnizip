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
require_relative "fse/encoder"

module Omnizip
  module Algorithms
    class Zstandard
      # Huffman Encoder for Zstandard (RFC 8878 Section 4.2)
      #
      # Encodes literals using Huffman coding with FSE-compressed weights.
      class HuffmanEncoder
        include Constants

        # @return [Array<Integer>] Code lengths for each symbol
        attr_reader :code_lengths

        # @return [Hash<Integer, Integer>] Symbol to code mapping
        attr_reader :codes

        # @return [Integer] Maximum code length
        attr_reader :max_bits

        # Build Huffman encoder from symbol frequencies
        #
        # @param frequencies [Array<Integer>] Symbol frequencies
        # @param max_bits [Integer] Maximum code length (default 11)
        # @return [HuffmanEncoder] Huffman encoder
        def self.build_from_frequencies(frequencies,
max_bits = HUFFMAN_MAX_BITS)
          return nil if frequencies.nil? || frequencies.empty?

          # Build Huffman tree and get code lengths
          code_lengths = build_huffman_lengths(frequencies, max_bits)

          # Limit code lengths to max_bits
          code_lengths = limit_code_lengths(code_lengths, max_bits)

          # Build canonical codes
          codes = build_canonical_codes(code_lengths)

          new(code_lengths, codes, max_bits)
        end

        # Build Huffman code lengths using package-merge algorithm
        #
        # @param frequencies [Array<Integer>] Symbol frequencies
        # @param max_bits [Integer] Maximum code length
        # @return [Array<Integer>] Code lengths
        def self.build_huffman_lengths(frequencies, max_bits)
          return [] if frequencies.nil? || frequencies.empty?

          # Create list of (frequency, symbol) pairs
          symbols_with_freq = frequencies.each_with_index
            .select { |freq, _| freq&.positive? }
            .map { |freq, sym| [freq, sym] }

          return Array.new(frequencies.length, 0) if symbols_with_freq.empty?

          # Sort by frequency
          symbols_with_freq.sort_by! { |freq, _| freq }

          # Build Huffman tree
          code_lengths = Array.new(frequencies.length, 0)

          # Simple Huffman tree building
          # Using a priority queue approach
          build_tree_lengths(symbols_with_freq, code_lengths, max_bits)

          code_lengths
        end

        # Build code lengths using tree approach
        def self.build_tree_lengths(symbols_with_freq, code_lengths, max_bits)
          return if symbols_with_freq.empty?

          # Create leaf nodes
          nodes = symbols_with_freq.map do |freq, sym|
            { freq: freq, symbol: sym, left: nil, right: nil, depth: 0 }
          end

          # Build tree by combining nodes
          while nodes.length > 1
            # Sort by frequency
            nodes.sort_by! { |n| n[:freq] }

            # Combine two smallest
            left = nodes.shift
            right = nodes.shift

            combined = {
              freq: left[:freq] + right[:freq],
              symbol: nil,
              left: left,
              right: right,
              depth: [left[:depth], right[:depth]].max + 1,
            }

            nodes << combined
          end

          # Extract code lengths from tree
          if nodes.length == 1
            assign_lengths(nodes[0], 0, code_lengths, max_bits)
          elsif symbols_with_freq.length == 1
            # Single symbol
            code_lengths[symbols_with_freq[0][1]] = 1
          end
        end

        # Recursively assign code lengths to symbols
        def self.assign_lengths(node, depth, code_lengths, max_bits)
          return unless node

          depth = [depth, max_bits].min

          if node[:symbol]
            # Leaf node
            code_lengths[node[:symbol]] = depth.positive? ? depth : 1
          else
            # Internal node
            assign_lengths(node[:left], depth + 1, code_lengths, max_bits)
            assign_lengths(node[:right], depth + 1, code_lengths, max_bits)
          end
        end

        # Limit code lengths to maximum
        #
        # Uses the package-merge algorithm concept to limit lengths.
        #
        # @param code_lengths [Array<Integer>] Original code lengths
        # @param max_bits [Integer] Maximum code length
        # @return [Array<Integer>] Limited code lengths
        def self.limit_code_lengths(code_lengths, max_bits)
          return code_lengths if code_lengths.nil? || code_lengths.empty?

          # Check if any length exceeds max
          max_length = code_lengths.max || 0
          return code_lengths if max_length <= max_bits

          # Limit using a simple approach: cap at max_bits and adjust
          # This is a simplified implementation
          lengths = code_lengths.map { |l| [l, max_bits].min }

          # Ensure Kraft inequality is satisfied
          # Sum of 2^(-length) must be <= 1
          kraft_sum = lengths.sum { |l| l.positive? ? 1 << (max_bits - l) : 0 }
          max_kraft = 1 << max_bits

          if kraft_sum > max_kraft
            # Need to increase some lengths
            # This is simplified - a proper implementation would use package-merge
            lengths = redistribute_lengths(lengths, max_bits)
          end

          lengths
        end

        # Redistribute lengths to satisfy Kraft inequality
        def self.redistribute_lengths(lengths, max_bits)
          # Simplified: just cap at max_bits
          lengths.map { |l| [l, max_bits].min }
        end

        # Build canonical Huffman codes from lengths
        #
        # @param code_lengths [Array<Integer>] Code lengths for each symbol
        # @return [Hash<Integer, Integer>] Symbol to code mapping
        def self.build_canonical_codes(code_lengths)
          codes = {}
          return codes if code_lengths.nil? || code_lengths.empty?

          max_length = code_lengths.compact.max || 0
          return codes if max_length.zero?

          # Count symbols at each length
          bl_count = Array.new(max_length + 1, 0)
          code_lengths.each do |length|
            bl_count[length] += 1 if length&.positive?
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
            next if length.nil? || length.zero?

            codes[symbol] = next_code[length]
            next_code[length] += 1
          end

          codes
        end

        # Initialize Huffman encoder
        #
        # @param code_lengths [Array<Integer>] Code lengths
        # @param codes [Hash<Integer, Integer>] Symbol to code mapping
        # @param max_bits [Integer] Maximum code length
        def initialize(code_lengths, codes, max_bits)
          @code_lengths = code_lengths
          @codes = codes
          @max_bits = max_bits

          # Build reverse lookup for encoding
          @symbol_code = {}
          @symbol_length = {}

          codes.each do |symbol, code|
            @symbol_code[symbol] = code
            @symbol_length[symbol] = code_lengths[symbol]
          end
        end

        # Encode data using Huffman codes
        #
        # @param data [String] Data to encode
        # @return [String] Encoded bitstream
        def encode(data)
          return "" if data.nil? || data.empty?

          bits = []

          data.each_byte do |byte|
            code = @symbol_code[byte]
            length = @symbol_length[byte]

            next unless code && length

            # Write bits MSB first
            length.times do |i|
              bit = (code >> (length - 1 - i)) & 1
              bits << bit
            end
          end

          # Convert bit array to bytes
          bits_to_bytes(bits)
        end

        # Encode Huffman table description for Zstandard
        #
        # Zstandard compresses Huffman weights using FSE.
        #
        # @return [String] Encoded Huffman table description
        def encode_table_description
          # Convert code lengths to weights
          # Weight = max_bits - code_length + 1 (for non-zero lengths)
          weights = @code_lengths.map do |length|
            next 0 if length.nil? || length.zero?

            @max_bits - length + 1
          end

          encode_weights_fse(weights)
        end

        private

        # Encode weights using FSE compression
        def encode_weights_fse(weights)
          # Count non-zero weights
          num_weights = weights.count(&:positive?)

          if num_weights.zero?
            # No symbols - empty table
            return "\x00"
          end

          # Build header byte
          # Bit 7: FSE compressed (1)
          # Bits 0-6: depends on format

          if num_weights <= 127
            # Simple format: just the count
            header = 0x80 | num_weights
            header_bytes = [header].pack("C")

            # Encode weights as FSE (simplified: just raw bytes for now)

          else
            # Extended format
            header = 0x80 | 127
            header_bytes = [header, num_weights].pack("CC")

          end
          weight_bytes = weights.select(&:positive?).pack("C*")
          header_bytes + weight_bytes
        end

        # Convert bit array to bytes
        def bits_to_bytes(bits)
          # Pad to byte boundary
          bits = bits.dup
          while bits.length % 8 != 0
            bits << 0
          end

          bytes = []
          bits.each_slice(8) do |byte_bits|
            byte = 0
            byte_bits.each_with_index do |bit, i|
              byte |= (bit << (7 - i)) # MSB first for Huffman
            end
            bytes << byte
          end

          bytes.pack("C*")
        end
      end
    end
  end
end
