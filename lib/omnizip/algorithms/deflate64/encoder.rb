# frozen_string_literal: true

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

          # Step 3: Write to output
          @output_stream.write(compressed)
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