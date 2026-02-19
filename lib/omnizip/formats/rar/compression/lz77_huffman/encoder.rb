# frozen_string_literal: true

require_relative "../bit_stream"
require_relative "match_finder"
require_relative "huffman_builder"

module Omnizip
  module Formats
    module Rar
      module Compression
        module LZ77Huffman
          # RAR LZ77+Huffman encoder
          #
          # Implements compression using LZ77 string matching combined with
          # Huffman coding for symbol encoding.
          #
          # ## Simplified Huffman Tree Format (MVP)
          #
          # This implementation uses a simplified tree format for portability
          # and ease of implementation. The format differs from official RAR
          # but maintains full compatibility between encoder and decoder.
          #
          # ### Format Structure:
          # ```
          # [16-bit num_symbols] [code_lengths...]
          #       2 bytes         512 × 4 bits = 256 bytes
          # ```
          #
          # ### Details:
          # - **Header**: 16-bit number of symbols (always 512 for MVP)
          #   - 0-255: Literal bytes
          #   - 256: End-of-block marker
          #   - 257-511: LZ77 match symbols
          #
          # - **Code Lengths**: 4 bits per symbol × 512 symbols = 2048 bits
          #   - Each symbol gets a 4-bit code length (0-15)
          #   - Length 0 means symbol not used
          #   - Lengths build canonical Huffman tree
          #
          # ### Trade-offs:
          # - **Fixed Overhead**: 258 bytes (2 + 256) per block
          # - **Simplicity**: Easy to implement and debug
          # - **Portability**: Pure Ruby, no external dependencies
          # - **Compatibility**: Encoder/decoder use identical format
          #
          # ### Real RAR Format Differences:
          # Real RAR uses a more complex format with:
          # - RLE compression of code lengths
          # - Multiple Huffman tables (MC, LD, RC, LDD)
          # - Adaptive tree updates
          # - More efficient length encoding
          #
          # The simplified format is sufficient for MVP and can be upgraded
          # to full RAR format in future versions without breaking the API.
          #
          # @see Decoder for decoding implementation
          # @see HuffmanCoder for tree building
          # @see HuffmanBuilder for code generation
          class Encoder
            LITERAL_SYMBOLS = (0..255)
            END_OF_BLOCK = 256
            MATCH_SYMBOLS = (257..511)
            MIN_MATCH_LENGTH = 3
            MAX_MATCH_LENGTH = 257

            attr_reader :compressed_size

            def initialize(output, _options = {})
              @output = output
              @bit_stream = BitStream.new(output, :write)
              @match_finder = MatchFinder.new
              @huffman_builder = HuffmanBuilder.new
              @compressed_size = 0
            end

            def encode(input)
              data = input.is_a?(String) ? input : input.read
              return 0 if data.empty?

              start_pos = @output.pos
              items = collect_items(data)
              codes = @huffman_builder.generate_codes
              write_huffman_tree(codes)

              items.each do |item|
                if item[:type] == :literal
                  encode_literal(item[:value], codes)
                else
                  encode_match(item[:offset], item[:length], codes)
                end
              end

              encode_symbol(END_OF_BLOCK, codes)
              @bit_stream.flush
              @compressed_size = @output.pos - start_pos
            end

            private

            def collect_items(data)
              items = []
              position = 0

              while position < data.size
                match = @match_finder.find_match(data.bytes, position)

                if match && match.length >= MIN_MATCH_LENGTH
                  items << { type: :match, offset: match.offset,
                             length: match.length }
                  match_symbol = encode_match_symbol(match.length)
                  @huffman_builder.add_symbol(match_symbol)
                  position += match.length
                else
                  byte = data.bytes[position]
                  items << { type: :literal, value: byte }
                  @huffman_builder.add_symbol(byte)
                  position += 1
                end
              end

              @huffman_builder.add_symbol(END_OF_BLOCK)
              items
            end

            def write_huffman_tree(codes)
              lengths = Array.new(512, 0)
              codes.each { |symbol, (_code, length)| lengths[symbol] = length }
              @bit_stream.write_bits(512, 16)
              lengths.each { |length| @bit_stream.write_bits(length, 4) }
            end

            def encode_literal(byte, codes)
              encode_symbol(byte, codes)
            end

            def encode_match(offset, length, codes)
              match_symbol = encode_match_symbol(length)
              encode_symbol(match_symbol, codes)
              @bit_stream.write_bits(offset, 16) # Changed from 8 to 16 bits for 64KB window
            end

            def encode_match_symbol(length)
              base_symbol = length - MIN_MATCH_LENGTH + 257
              [base_symbol, 511].min
            end

            def encode_symbol(symbol, codes)
              code, length = codes[symbol]
              return unless code && length

              @bit_stream.write_bits(code, length)
            end
          end
        end
      end
    end
  end
end
