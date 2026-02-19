# frozen_string_literal: true

require "json"
require_relative "constants"
require_relative "lz77_encoder"
require_relative "huffman_coder"

module Omnizip
  module Algorithms
    class Deflate64
      # Deflate64 encoder
      class Encoder
        include Constants

        attr_reader :window_size

        def initialize(output_stream, options = {})
          @output_stream = output_stream
          @window_size = options[:window_size] || DICTIONARY_SIZE
          @compression_level = options[:level] || 6
          @lz77_encoder = LZ77Encoder.new(@window_size)
          @huffman = HuffmanCoder.new
        end

        # Compress input stream to output stream
        #
        # @param input_stream [IO] Input data stream
        def compress(input_stream)
          data = input_stream.read

          # Step 1: LZ77 compression with 64KB window
          tokens = @lz77_encoder.find_matches(data)

          # Step 2: Huffman coding
          compressed = @huffman.encode(tokens)

          # Step 3: Serialize trees and write to output
          output = serialize_with_trees(
            compressed,
            @huffman.literal_tree,
            @huffman.distance_tree,
          )

          @output_stream.write(output)
        end

        private

        # Serialize compressed data with Huffman trees
        #
        # @param compressed [String] Compressed data
        # @param literal_tree [Hash] Literal Huffman tree
        # @param distance_tree [Hash] Distance Huffman tree
        # @return [String] Serialized output
        def serialize_with_trees(compressed, literal_tree, distance_tree)
          literal_json = literal_tree.to_json
          distance_json = distance_tree.to_json

          # Pack: literal_size (4 bytes), distance_size (4 bytes),
          #       literal_tree, distance_tree, compressed_data
          [
            literal_json.bytesize,
            distance_json.bytesize,
            literal_json,
            distance_json,
            compressed,
          ].pack("NNA#{literal_json.bytesize}A#{distance_json.bytesize}A*")
        end

        # Encode data block
        #
        # @param data [String] Input data
        # @return [String] Compressed data
        def encode_block(data)
          # Find LZ77 matches
          tokens = @lz77_encoder.find_matches(data)

          # Huffman encode
          @huffman.encode(tokens)
        end

        # Encode stream in chunks
        #
        # @param input_stream [IO] Input stream
        # @param chunk_size [Integer] Size of chunks to process
        def encode_stream(input_stream, chunk_size = 65_536)
          until input_stream.eof?
            chunk = input_stream.read(chunk_size)
            break if chunk.nil? || chunk.empty?

            compressed = encode_block(chunk)
            @output_stream.write(compressed)
          end
        end
      end
    end
  end
end
