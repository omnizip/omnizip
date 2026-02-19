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
          encode_tokens(tokens)
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
              right: right,
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
            generate_codes(node[:left], "#{code}0", codes)
            generate_codes(node[:right], "#{code}1", codes)
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

            # Check for decoding failure
            if symbol.nil?
              raise Omnizip::DecompressionError,
                    "Failed to decode symbol at bit position #{pos}"
            end

            pos += length

            break if symbol == END_OF_BLOCK

            if symbol < 256
              tokens << { type: :literal, value: symbol }
            else
              match_length = code_to_length(symbol)

              dist_symbol, dist_length =
                decode_symbol(bits, pos, @distance_tree)

              # Check for distance decoding failure
              if dist_symbol.nil?
                raise Omnizip::DecompressionError,
                      "Failed to decode distance at bit position #{pos}"
              end

              pos += dist_length

              distance = code_to_distance(dist_symbol)

              tokens << {
                type: :match,
                length: match_length,
                distance: distance,
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
        # Uses DEFLATE distance code table
        def distance_to_code(distance)
          case distance
          when 1..4
            distance - 1
          when 5..8
            4 + ((distance - 5) / 2)
          when 9..16
            6 + ((distance - 9) / 4)
          when 17..32
            8 + ((distance - 17) / 8)
          when 33..64
            10 + ((distance - 33) / 16)
          when 65..128
            12 + ((distance - 65) / 32)
          when 129..256
            14 + ((distance - 129) / 64)
          when 257..512
            16 + ((distance - 257) / 128)
          when 513..1024
            18 + ((distance - 513) / 256)
          when 1025..2048
            20 + ((distance - 1025) / 512)
          when 2049..4096
            22 + ((distance - 2049) / 1024)
          when 4097..8192
            24 + ((distance - 4097) / 2048)
          when 8193..16384
            26 + ((distance - 8193) / 4096)
          when 16385..32768
            28 + ((distance - 16385) / 8192)
          when 32769..65536
            29
          else
            29 # Max distance code for 64KB window
          end
        end

        # Convert Huffman code to distance
        # Uses DEFLATE distance code table (base distances)
        def code_to_distance(code)
          case code
          when 0..3
            code + 1
          when 4..5
            5 + ((code - 4) * 2)
          when 6..7
            9 + ((code - 6) * 4)
          when 8..9
            17 + ((code - 8) * 8)
          when 10..11
            33 + ((code - 10) * 16)
          when 12..13
            65 + ((code - 12) * 32)
          when 14..15
            129 + ((code - 14) * 64)
          when 16..17
            257 + ((code - 16) * 128)
          when 18..19
            513 + ((code - 18) * 256)
          when 20..21
            1025 + ((code - 20) * 512)
          when 22..23
            2049 + ((code - 22) * 1024)
          when 24..25
            4097 + ((code - 24) * 2048)
          when 26..27
            8193 + ((code - 26) * 4096)
          when 28..29
            16385 + ((code - 28) * 8192)
          else
            1 # Default to distance 1
          end
        end

        # Convert bit string to bytes
        def bits_to_bytes(bits)
          bytes = bits.scan(/.{1,8}/).map do |byte_bits|
            byte_bits.ljust(8, "0").to_i(2)
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
