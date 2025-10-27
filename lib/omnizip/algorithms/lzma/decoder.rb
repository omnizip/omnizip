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
require_relative "range_decoder"
require_relative "state"
require_relative "bit_model"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZMA Decoder - decompresses LZMA-encoded data
      #
      # This class implements the LZMA decoding algorithm by:
      # 1. Reading and parsing the LZMA header
      # 2. Using range decoder for probability-based bit decoding
      # 3. Reconstructing the original data from literals and matches
      #
      # The decoder reads a stream that consists of:
      # - Property byte (lc, lp, pb parameters)
      # - Dictionary size (4 bytes)
      # - Uncompressed size (8 bytes)
      # - Compressed data
      class Decoder
        include Constants

        attr_reader :dict_size, :lc, :lp, :pb, :uncompressed_size

        # Initialize the decoder
        #
        # @param input [IO] Input stream of compressed data
        def initialize(input)
          @input = input
          read_header
          init_decoder
        end

        # Decode a compressed stream
        #
        # @return [String] Decompressed data
        def decode_stream
          @range_decoder = RangeDecoder.new(@input)
          @state = State.new
          @output = []

          decode_data

          @output.pack("C*").force_encoding("ASCII-8BIT")
        end

        private

        # Read and parse LZMA header
        #
        # @return [void]
        # @raise [RuntimeError] If header is invalid
        def read_header
          # Property byte
          props = @input.getbyte
          raise "Invalid LZMA header" if props.nil?

          @lc = props % 9
          rem = props / 9
          @lp = rem % 5
          @pb = rem / 5

          # Dictionary size (4 bytes, little-endian)
          @dict_size = 0
          4.times do |i|
            byte = @input.getbyte
            raise "Incomplete header" if byte.nil?

            @dict_size |= (byte << (i * 8))
          end

          # Uncompressed size (8 bytes, little-endian)
          @uncompressed_size = 0
          8.times do |i|
            byte = @input.getbyte
            raise "Incomplete header" if byte.nil?

            @uncompressed_size |= (byte << (i * 8))
          end
        end

        # Initialize decoder state
        #
        # @return [void]
        def init_decoder
          @literal_models = Array.new(1 << (@lc + @lp)) do
            Array.new(256) { BitModel.new }
          end
          @match_model = BitModel.new
          @rep_model = BitModel.new
          @len_models = Array.new(16) { BitModel.new }
          @dist_models = Array.new(128) { BitModel.new }
        end

        # Decode the main data
        #
        # @return [void]
        def decode_data
          while @output.size < @uncompressed_size
            is_match = @range_decoder.decode_bit(@match_model)

            if is_match.zero?
              decode_literal
            else
              decode_match
            end
          end
        end

        # Decode a literal byte
        #
        # @return [void]
        def decode_literal
          lit_state = get_literal_state
          byte = decode_literal_byte(lit_state)

          @output << byte
          @state.update_literal
        end

        # Decode a match
        #
        # @return [void]
        def decode_match
          length = decode_length + MATCH_LEN_MIN
          distance = decode_distance + 1

          # Copy from output buffer (dictionary)
          length.times do
            src_pos = @output.size - distance
            byte = src_pos >= 0 ? (@output[src_pos] || 0) : 0
            @output << byte
          end

          @state.update_match
        end

        # Get literal state based on position
        #
        # @return [Integer] Literal state index
        def get_literal_state
          pos = @output.size
          prev_byte = pos.positive? ? @output[pos - 1] : 0
          ((pos & ((1 << @lp) - 1)) << @lc) + (prev_byte >> (8 - @lc))
        end

        # Decode a literal byte value
        #
        # @param lit_state [Integer] Literal state
        # @return [Integer] Decoded byte
        def decode_literal_byte(lit_state)
          models = @literal_models[lit_state % @literal_models.size]
          symbol = 1

          8.times do
            bit = @range_decoder.decode_bit(models[symbol])
            symbol = (symbol << 1) | bit
          end

          symbol - 256
        end

        # Decode match length
        #
        # @return [Integer] Length value (before adding MIN)
        def decode_length
          # Use fixed 8-bit decoding for simplicity
          @range_decoder.decode_direct_bits(8)
        end

        # Decode match distance
        #
        # @return [Integer] Distance value (before adding 1)
        def decode_distance
          # Use fixed 16-bit decoding for simplicity
          @range_decoder.decode_direct_bits(16)
        end
      end
    end
  end
end
