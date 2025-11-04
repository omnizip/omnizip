# frozen_string_literal: true

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

          # Decode Huffman-encoded data
          tokens = @huffman.decode(
            compressed_data,
            {}, # literal tree (to be read from stream)
            {}  # distance tree (to be read from stream)
          )

          # Reconstruct data from LZ77 tokens
          decompressed = reconstruct_from_tokens(tokens)

          output_stream.write(decompressed)
        end

        # Reconstruct data from LZ77 tokens
        #
        # @param tokens [Array<Hash>] LZ77 tokens
        # @return [String] Decompressed data
        def reconstruct_from_tokens(tokens)
          output = []

          tokens.each do |token|
            if token[:type] == :literal
              output << token[:value].chr
              @window << token[:value]
            elsif token[:type] == :match
              copy_from_window(
                output,
                token[:distance],
                token[:length]
              )
            end

            # Maintain 64KB window
            @window.shift if @window.size > @window_size
          end

          output.join
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

          length.times do |i|
            byte = @window[start_pos + i]
            output << byte.chr
            @window << byte
          end
        end
      end
    end
  end
end