# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Compression
        module LZ77Huffman
          # Huffman tree builder for dynamic compression
          #
          # Builds canonical Huffman trees from symbol frequencies.
          # Uses priority queue (heap) algorithm to construct optimal trees.
          #
          # Responsibilities:
          # - ONE responsibility: Build Huffman trees and generate codes
          # - Collect symbol frequencies
          # - Build optimal Huffman tree
          # - Generate canonical Huffman codes
          # - Calculate code lengths
          class HuffmanBuilder
            MAX_CODE_LENGTH = 15

            # Tree node for Huffman tree construction
            class Node
              attr_accessor :symbol, :frequency, :left, :right

              def initialize(symbol, frequency)
                @symbol = symbol
                @frequency = frequency
                @left = nil
                @right = nil
              end

              def leaf?
                @left.nil? && @right.nil?
              end
            end

            attr_reader :frequencies

            def initialize
              @frequencies = Hash.new(0)
            end

            # Add symbol occurrence(s)
            #
            # @param symbol [Integer] Symbol value
            # @param count [Integer] Number of occurrences
            # @return [void]
            def add_symbol(symbol, count = 1)
              @frequencies[symbol] += count
            end

            # Build Huffman tree from frequencies
            #
            # Uses priority queue algorithm to build optimal tree.
            # Returns root node of the tree.
            #
            # @return [Node, nil] Root node or nil if empty
            def build_tree
              return nil if @frequencies.empty?

              if @frequencies.size == 1
                return Node.new(@frequencies.keys.first,
                                @frequencies.values.first)
              end

              # Create leaf nodes
              heap = @frequencies.map { |symbol, freq| Node.new(symbol, freq) }
              heap.sort_by!(&:frequency)

              # Build tree bottom-up
              while heap.size > 1
                left = heap.shift
                right = heap.shift

                parent = Node.new(nil, left.frequency + right.frequency)
                parent.left = left
                parent.right = right

                # Insert maintaining heap property
                insert_into_heap(heap, parent)
              end

              heap.first
            end

            # Generate canonical Huffman codes
            #
            # Returns hash mapping symbols to [code, length] pairs.
            # Codes are canonical (same-length codes are sequential).
            #
            # @return [Hash<Integer, Array(Integer, Integer)>] symbol => [code, length]
            def generate_codes
              root = build_tree
              return {} if root.nil?

              # Handle single symbol case
              if root.leaf?
                return { root.symbol => [0, 1] }
              end

              # Calculate code lengths for each symbol
              code_lengths = {}
              calculate_code_lengths(root, 0, code_lengths)

              # Generate canonical codes from lengths
              generate_canonical_codes(code_lengths)
            end

            # Get code lengths only (for header transmission)
            #
            # @return [Hash<Integer, Integer>] symbol => length
            def code_lengths
              root = build_tree
              return {} if root.nil?

              if root.leaf?
                return { root.symbol => 1 }
              end

              lengths = {}
              calculate_code_lengths(root, 0, lengths)
              lengths
            end

            # Reset builder
            #
            # @return [void]
            def reset
              @frequencies.clear
            end

            # Check if empty
            #
            # @return [Boolean]
            def empty?
              @frequencies.empty?
            end

            # Get number of symbols
            #
            # @return [Integer]
            def symbol_count
              @frequencies.size
            end

            private

            # Insert node into heap maintaining sort order
            #
            # @param heap [Array<Node>] Heap array
            # @param node [Node] Node to insert
            # @return [void]
            def insert_into_heap(heap, node)
              index = heap.bsearch_index do |n|
                n.frequency >= node.frequency
              end || heap.size
              heap.insert(index, node)
            end

            # Calculate code lengths via tree traversal
            #
            # @param node [Node] Current node
            # @param depth [Integer] Current depth
            # @param lengths [Hash] Output hash
            # @return [void]
            def calculate_code_lengths(node, depth, lengths)
              return if node.nil?

              if node.leaf?
                lengths[node.symbol] = [depth, MAX_CODE_LENGTH].min
              else
                calculate_code_lengths(node.left, depth + 1, lengths)
                calculate_code_lengths(node.right, depth + 1, lengths)
              end
            end

            # Generate canonical codes from code lengths
            #
            # Canonical codes have the property that codes of the same
            # length are sequential integers.
            #
            # @param code_lengths [Hash<Integer, Integer>] symbol => length
            # @return [Hash<Integer, Array(Integer, Integer)>] symbol => [code, length]
            def generate_canonical_codes(code_lengths)
              return {} if code_lengths.empty?

              # Count symbols at each length
              length_counts = Array.new(MAX_CODE_LENGTH + 1, 0)
              code_lengths.each_value { |len| length_counts[len] += 1 }

              # Calculate first code for each length
              first_codes = Array.new(MAX_CODE_LENGTH + 1, 0)
              code = 0
              (1..MAX_CODE_LENGTH).each do |len|
                first_codes[len] = code
                code = (code + length_counts[len]) << 1
              end

              # Assign codes to symbols
              codes = {}
              code_lengths.sort_by do |sym, len|
                [len, sym]
              end.each do |symbol, length|
                code = first_codes[length]
                first_codes[length] += 1
                codes[symbol] = [code, length]
              end

              codes
            end
          end
        end
      end
    end
  end
end
