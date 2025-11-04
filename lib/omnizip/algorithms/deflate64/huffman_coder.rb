# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Algorithms
    class Deflate64
      # Huffman coding for Deflate64
      class HuffmanCoder
        include Constants

        # Length code mapping
        LENGTH_CODES_MAP = {
          3 => 257, 4 => 258, 5 => 259, 6 => 260, 7 => 261,
          8 => 262, 9 => 263, 10 => 264, 11 => 265, 12 => 266,
          13 => 267, 14 => 268, 15 => 269, 16 => 270, 17 => 271,
          18 => 272, 19 => 273, 20 => 274, 21 => 275, 22 => 276,
          23 => 277, 24 => 278, 25 => 279, 26 => 280, 27 => 281,
          28 => 282, 29 => 283, 30 => 284, 31 => 285
        }.freeze

        # Distance code mapping
        DISTANCE_CODES_MAP = (0..29).to_a.freeze

        attr_reader :literal_tree, :distance_tree

        def initialize
          @literal_tree = nil
          @distance_tree = nil
        end

        # Encode tokens using Huffman coding
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [String] Encoded bitstream
        def encode(tokens)
          # Build frequency tables
          literal_freqs = build_literal_frequencies(tokens)
          distance_freqs = build_distance_frequencies(tokens)

          # Build Huffman trees
          @literal_tree = build_tree(literal_freqs)
          @distance_tree = build_tree(distance_freqs)

          # Encode tokens
          bitstream = encode_tokens(tokens)

          bitstream
        end

        # Decode bitstream using Huffman coding
        #
        # @param bitstream [String] Encoded data
        # @param literal_tree [Hash] Literal Huffman tree
        # @param distance_tree [Hash] Distance Huffman tree
        # @return [Array<Hash>] Decoded tokens
        def decode(bitstream, literal_tree, distance_tree)
          @literal_tree = literal_tree
          @distance_tree = distance_tree

          decode_tokens(bitstream)
        end

        private

        # Build frequency table for literals and lengths
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [Hash] Frequency table
        def build_literal_frequencies(tokens)
          freqs = Hash.new(0)

          tokens.each do |token|
            if token[:type] == :literal
              freqs[token[:value]] += 1
            else
              length_code = length_to_code(token[:length])
              freqs[length_code] += 1
            end
          end

          # Add end of block marker
          freqs[END_OF_BLOCK] = 1

          freqs
        end

        # Build frequency table for distances
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [Hash] Frequency table
        def build_distance_frequencies(tokens)
          freqs = Hash.new(0)

          tokens.each do |token|
            next unless token[:type] == :match

            distance_code = distance_to_code(token[:distance])
            freqs[distance_code] += 1
          end

          freqs
        end

        # Build Huffman tree from frequencies
        #
        # @param frequencies [Hash] Symbol frequencies
        # @return [Hash] Huffman code table
        def build_tree(frequencies)
          return {} if frequencies.empty?

          # Build priority queue of nodes
          nodes = frequencies.map do |symbol, freq|
            { symbol: symbol, freq: freq, left: nil, right: nil }
          end

          # Build tree using priority queue
          while nodes.size > 1
            nodes.sort_by! { |n| n[:freq] }
            left = nodes.shift
            right = nodes.shift

            parent = {
              symbol: nil,
              freq: left[:freq] + right[:freq],
              left: left,
              right: right
            }

            nodes << parent
          end

          # Generate codes from tree
          generate_codes(nodes.first)
        end

        # Generate Huffman codes from tree
        #
        # @param node [Hash] Tree node
        # @param code [String] Current code
        # @param codes [Hash] Code table
        # @return [Hash] Complete code table
        def generate_codes(node, code = "", codes = {})
          return codes if node.nil?

          if node[:symbol]
            codes[node[:symbol]] = code
          else
            generate_codes(node[:left], code + "0", codes)
            generate_codes(node[:right], code + "1", codes)
          end

          codes
        end

        # Encode tokens to bitstream
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [String] Encoded bitstream
        def encode_tokens(tokens)
          bits = ""

          tokens.each do |token|
            if token[:type] == :literal
              bits += @literal_tree[token[:value]]
            else
              length_code = length_to_code(token[:length])
              bits += @literal_tree[length_code]

              distance_code = distance_to_code(token[:distance])
              bits += @distance_tree[distance_code]
            end
          end

          # Add end of block marker
          bits += @literal_tree[END_OF_BLOCK]

          # Convert bits to bytes
          bits_to_bytes(bits)
        end

        # Decode tokens from bitstream
        #
        # @param bitstream [String] Encoded data
        # @return [Array<Hash>] Decoded tokens
        def decode_tokens(bitstream)
          tokens = []
          bits = bytes_to_bits(bitstream)
          pos = 0

          while pos < bits.length
            symbol, length = decode_symbol(bits, pos, @literal_tree)
            pos += length

            break if symbol == END_OF_BLOCK

            if symbol < 256
              tokens << { type: :literal, value: symbol }
            else
              match_length = code_to_length(symbol)

              dist_symbol, dist_length =
                decode_symbol(bits, pos, @distance_tree)
              pos += dist_length

              distance = code_to_distance(dist_symbol)

              tokens << {
                type: :match,
                length: match_length,
                distance: distance
              }
            end
          end

          tokens
        end

        # Decode single symbol from bitstream
        #
        # @param bits [String] Bit string
        # @param pos [Integer] Current position
        # @param tree [Hash] Huffman tree
        # @return [Array] Symbol and bits consumed
        def decode_symbol(bits, pos, tree)
          code = ""
          reverse_tree = tree.invert

          while pos < bits.length
            code += bits[pos]
            pos += 1

            if reverse_tree[code]
              return [reverse_tree[code], code.length]
            end
          end

          [nil, 0]
        end

        # Convert match length to Huffman code
        def length_to_code(length)
          LENGTH_CODES_MAP[length] || 285
        end

        # Convert Huffman code to match length
        def code_to_length(code)
          LENGTH_CODES_MAP.key(code) || 258
        end

        # Convert distance to Huffman code
        def distance_to_code(distance)
          Math.log2(distance).to_i
        end

        # Convert Huffman code to distance
        def code_to_distance(code)
          2**code
        end

        # Convert bit string to bytes
        def bits_to_bytes(bits)
          bytes = []
          bits.scan(/.{1,8}/).each do |byte_bits|
            bytes << byte_bits.ljust(8, "0").to_i(2)
          end
          bytes.pack("C*")
        end

        # Convert bytes to bit string
        def bytes_to_bits(bytes)
          bytes.unpack("C*").map { |b| b.to_s(2).rjust(8, "0") }.join
        end
      end
    end
  end
end