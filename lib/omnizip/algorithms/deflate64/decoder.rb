# frozen_string_literal: true

require "json"
require_relative "constants"
require_relative "huffman_coder"

module Omnizip
  module Algorithms
    class Deflate64
      # Deflate64 decoder
      class Decoder
        include Constants

        attr_reader :window_size

        def initialize(input_stream)
          @input_stream = input_stream
          @window_size = DICTIONARY_SIZE
          @window = []
          @huffman = HuffmanCoder.new
        end

        # Decompress input stream to output stream
        #
        # @param output_stream [IO] Output data stream
        def decompress(output_stream)
          compressed_data = @input_stream.read

          # Deserialize trees and compressed data
          literal_tree, distance_tree, data = deserialize_with_trees(compressed_data)

          # Decode Huffman-encoded data
          tokens = @huffman.decode(data, literal_tree, distance_tree)

          # Reconstruct data from LZ77 tokens
          decompressed = reconstruct_from_tokens(tokens)

          output_stream.write(decompressed)
        end

        # Deserialize compressed data with Huffman trees
        #
        # @param data [String] Serialized compressed data
        # @return [Array] Literal tree, distance tree, compressed data
        def deserialize_with_trees(data)
          # Extract sizes (4 bytes each)
          literal_size, distance_size = data.unpack("NN")
          offset = 8

          # Extract literal tree JSON
          literal_json = data[offset, literal_size]
          offset += literal_size

          # Extract distance tree JSON
          distance_json = data[offset, distance_size]
          offset += distance_size

          # Extract compressed data
          compressed = data[offset..]

          # Parse trees from JSON with symbol keys as integers
          literal_tree = parse_tree_from_json(literal_json)
          distance_tree = parse_tree_from_json(distance_json)

          [literal_tree, distance_tree, compressed]
        end

        # Parse Huffman tree from JSON with integer keys
        #
        # @param json [String] JSON string
        # @return [Hash] Huffman tree with integer keys
        def parse_tree_from_json(json)
          parsed = JSON.parse(json)
          # Convert string keys back to integers
          parsed.transform_keys(&:to_i)
        end

        # Reconstruct data from LZ77 tokens
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [String] Decompressed data
        def reconstruct_from_tokens(tokens)
          output = []

          tokens.each do |token|
            if token[:type] == :literal
              byte_char = token[:value].chr(Encoding::BINARY)
              output << byte_char
              @window << token[:value]
            elsif token[:type] == :match
              copy_from_window(
                output,
                token[:distance],
                token[:length],
              )
            end

            # Maintain 64KB window
            while @window.size > @window_size
              @window.shift
            end
          end

          output.join.force_encoding(Encoding::BINARY)
        end

        # Decode single block
        #
        # @param data [String] Compressed block
        # @return [String] Decompressed data
        def decode_block(data)
          tokens = @huffman.decode(data, {}, {})
          reconstruct_from_tokens(tokens)
        end

        private

        # Copy data from sliding window
        #
        # @param output [Array] Output buffer
        # @param distance [Integer] Distance back in window
        # @param length [Integer] Number of bytes to copy
        def copy_from_window(output, distance, length)
          start_pos = @window.size - distance

          # Check if we're trying to copy from beyond the window
          if start_pos.negative?
            raise Omnizip::DecompressionError,
                  "Invalid distance: #{distance} exceeds window size #{@window.size}"
          end

          length.times do |i|
            # Handle RLE case where we copy bytes we just wrote
            idx = (start_pos + i) % @window.size
            byte = @window[idx]

            if byte.nil?
              raise Omnizip::DecompressionError,
                    "Window access failed at index #{idx} (start: #{start_pos}, i: #{i})"
            end

            byte_char = byte.chr(Encoding::BINARY)
            output << byte_char
            @window << byte

            # Maintain window size during copy
            @window.shift if @window.size > @window_size
          end
        end
      end
    end
  end
end
