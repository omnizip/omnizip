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

require_relative "../bit_stream"
require_relative "sliding_window"
require_relative "huffman_coder"

module Omnizip
  module Formats
    module Rar
      module Compression
        module LZ77Huffman
          # RAR LZ77+Huffman decoder
          #
          # Orchestrates the decoding of RAR METHOD_NORMAL compressed data.
          # Combines Huffman coding with LZ77 sliding window compression.
          #
          # Responsibilities:
          # - ONE responsibility: Orchestrate LZ77+Huffman decoding
          # - Parse Huffman trees from bit stream
          # - Decode symbols using Huffman coder
          # - Process LZ77 matches via sliding window
          # - Manage decoder state and output
          #
          # RAR LZ77+Huffman Format:
          # 1. Block header with Huffman tree definitions
          # 2. Compressed data stream
          # 3. Symbols: literals (0-255), matches (length+distance), end marker
          class Decoder
            # Symbol ranges
            LITERAL_SYMBOLS = (0..255)
            END_OF_BLOCK = 256
            MATCH_SYMBOLS = (257..511)

            # Match parameters
            MIN_MATCH_LENGTH = 3
            MAX_MATCH_LENGTH = 257

            # Window size for RAR4
            DEFAULT_WINDOW_SIZE = 64 * 1024

            # Initialize LZ77+Huffman decoder
            #
            # @param input [IO] Compressed input stream
            # @param options [Hash] Decoding options
            # @option options [Integer] :window_size Window size in bytes
            def initialize(input, options = {})
              @bit_stream = BitStream.new(input, :read)
              @window = SlidingWindow.new(options[:window_size] || DEFAULT_WINDOW_SIZE)
              @huffman = HuffmanCoder.new
              @output = String.new(encoding: Encoding::BINARY)
            end

            # Decode compressed data
            #
            # Main decoding loop:
            # 1. Parse Huffman tree (simplified for MVP)
            # 2. Decode symbols until end-of-block
            # 3. Process literals and matches
            #
            # @param max_output [Integer, nil] Maximum output bytes
            # @return [String] Decoded data
            def decode(max_output = nil)
              @output.clear

              # Parse Huffman tree (simplified - real RAR has complex structure)
              parse_huffman_trees

              # Decode symbols until end-of-block or max output
              loop do
                break if max_output && @output.bytesize >= max_output

                symbol = @huffman.decode_symbol(@bit_stream)
                break if symbol.nil? || symbol == END_OF_BLOCK

                process_symbol(symbol)
              end

              @output
            rescue EOFError
              @output
            end

            # Get window size
            #
            # @return [Integer] Window size in bytes
            def window_size
              @window.size
            end

            private

            # Parse Huffman trees from bit stream
            #
            # RAR uses multiple Huffman tables for different symbol types.
            # This is a simplified implementation for MVP.
            #
            # Simplified format (written by Encoder):
            # 1. 16-bit number of symbols (always 512 for MVP)
            # 2. Code lengths (4 bits each, 512 × 4 bits = 2048 bits = 256 bytes)
            #
            # Real RAR format:
            # - MC table: Main code (literals + length codes)
            # - LD table: Low distance bits
            # - RC table: Repeat codes
            # - LDD table: Low distance for distance codes
            #
            # @return [void]
            def parse_huffman_trees
              # Read number of symbols from encoder (16-bit header)
              num_symbols = @bit_stream.read_bits(16)

              # Parse tree structure
              @huffman.parse_tree(@bit_stream, num_symbols)
            end

            # Process a decoded symbol
            #
            # Symbol types:
            # - 0-255: Literal byte
            # - 256: End of block
            # - 257-511: Match (length+distance)
            #
            # @param symbol [Integer] Decoded symbol
            # @return [void]
            def process_symbol(symbol)
              if LITERAL_SYMBOLS.cover?(symbol)
                process_literal(symbol)
              elsif MATCH_SYMBOLS.cover?(symbol)
                process_match(symbol)
              end
            end

            # Process literal byte
            #
            # @param byte [Integer] Literal byte value (0-255)
            # @return [void]
            def process_literal(byte)
              @output << byte.chr
              @window.add_byte(byte)
            end

            # Process LZ77 match
            #
            # Match symbol encodes both length and distance information.
            # Additional bits may be read for exact values.
            #
            # @param symbol [Integer] Match symbol (257-511)
            # @return [void]
            def process_match(symbol)
              length = decode_match_length(symbol)
              distance = decode_match_distance

              # Copy match from window
              match_bytes = @window.copy_match(distance, length)
              match_bytes.each { |byte| @output << byte.chr }
            end

            # Decode match length from symbol
            #
            # RAR encodes length in the symbol itself plus extra bits.
            # This is simplified for MVP.
            #
            # @param symbol [Integer] Match symbol
            # @return [Integer] Match length
            def decode_match_length(symbol)
              # Simplified length decoding
              # Real RAR uses complex length encoding with extra bits

              base_length = symbol - 257 + MIN_MATCH_LENGTH

              # Could read extra bits here for longer lengths
              # For now, use base length
              [base_length, MAX_MATCH_LENGTH].min
            end

            # Decode match distance
            #
            # Distance is encoded separately, often with additional
            # Huffman tables and extra bits.
            #
            # @return [Integer] Match distance
            def decode_match_distance
              # Simplified distance decoding
              # Real RAR uses separate Huffman table for distance

              # Read distance as direct bits (simplified)
              # Real implementation would use distance Huffman table
              distance_bits = 16 # Changed from 8 to 16 bits for 64KB window
              @bit_stream.read_bits(distance_bits)
            end
          end
        end
      end
    end
  end
end
