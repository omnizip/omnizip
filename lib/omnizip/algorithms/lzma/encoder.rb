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
require_relative "range_encoder"
require_relative "match_finder"
require_relative "state"
require_relative "bit_model"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZMA Encoder - combines dictionary compression with range coding
      #
      # This class implements the LZMA encoding algorithm by combining:
      # 1. LZ77 match finder for finding duplicate sequences
      # 2. State machine for tracking compression context
      # 3. Range encoder for probability-based bit encoding
      #
      # The encoder produces a stream that consists of:
      # - Property byte (lc, lp, pb parameters)
      # - Dictionary size (4 bytes)
      # - Uncompressed size (8 bytes)
      # - Compressed data
      class Encoder
        include Constants

        attr_reader :dict_size, :lc, :lp, :pb

        # Initialize the encoder
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :dict_size Dictionary size
        # @option options [Integer] :lc Literal context bits (0-8)
        # @option options [Integer] :lp Literal position bits (0-4)
        # @option options [Integer] :pb Position bits (0-4)
        def initialize(output, options = {})
          @output = output
          @dict_size = options[:dict_size] || (1 << 23)
          @lc = options[:lc] || 3
          @lp = options[:lp] || 0
          @pb = options[:pb] || 2

          validate_parameters
          init_encoder
        end

        # Encode a stream of data
        #
        # @param input [String, IO] Input data to compress
        # @return [void]
        def encode_stream(input)
          data = input.is_a?(String) ? input : input.read
          write_header(data.bytesize)

          @range_encoder = RangeEncoder.new(@output)
          @match_finder = MatchFinder.new(@dict_size)
          @state = State.new

          encode_data(data)

          @range_encoder.flush
        end

        private

        # Validate encoding parameters
        #
        # @return [void]
        # @raise [ArgumentError] If parameters are invalid
        def validate_parameters
          raise ArgumentError, "lc must be 0-8" unless @lc.between?(0, 8)
          raise ArgumentError, "lp must be 0-4" unless @lp.between?(0, 4)
          raise ArgumentError, "pb must be 0-4" unless @pb.between?(0, 4)
          return if @dict_size.between?(DICT_SIZE_MIN, DICT_SIZE_MAX)

          raise ArgumentError, "Invalid dictionary size"
        end

        # Initialize encoder state
        #
        # @return [void]
        def init_encoder
          @literal_models = Array.new(1 << (@lc + @lp)) do
            Array.new(256) { BitModel.new }
          end
          @match_model = BitModel.new
          @rep_model = BitModel.new
          @len_models = Array.new(16) { BitModel.new }
          @dist_models = Array.new(128) { BitModel.new }
        end

        # Write LZMA header
        #
        # @param uncompressed_size [Integer] Original data size
        # @return [void]
        def write_header(uncompressed_size)
          # Property byte: (lc + lp*9 + pb*45)
          props = @lc + (@lp * 9) + (@pb * 45)
          @output.putc(props)

          # Dictionary size (4 bytes, little-endian)
          4.times do |i|
            @output.putc((@dict_size >> (i * 8)) & 0xFF)
          end

          # Uncompressed size (8 bytes, little-endian)
          8.times do |i|
            @output.putc((uncompressed_size >> (i * 8)) & 0xFF)
          end
        end

        # Encode the main data
        #
        # @param data [String] Data to encode
        # @return [void]
        def encode_data(data)
          pos = 0
          bytes = data.bytes

          while pos < bytes.size
            match = @match_finder.find_longest_match(bytes, pos)

            if should_encode_match?(match, pos, bytes)
              encode_match(match, pos, bytes)
              pos += match.length
            else
              encode_literal(bytes[pos], pos, bytes)
              pos += 1
            end
          end
        end

        # Determine if a match should be encoded
        #
        # @param match [MatchFinder::Match, nil] Found match
        # @param pos [Integer] Current position
        # @param bytes [Array<Integer>] Data bytes
        # @return [Boolean] True if match should be encoded
        def should_encode_match?(_match, _pos, _bytes)
          # Temporarily disable match encoding for initial implementation
          # This ensures correctness first, optimization later
          false
        end

        # Encode a literal byte
        #
        # @param byte [Integer] Byte to encode
        # @param pos [Integer] Position in stream
        # @param bytes [Array<Integer>] All data bytes
        # @return [void]
        def encode_literal(byte, pos, bytes)
          @range_encoder.encode_bit(@match_model, 0)

          lit_state = get_literal_state(pos, bytes)
          encode_literal_byte(byte, lit_state)

          @state.update_literal
        end

        # Encode a match
        #
        # @param match [MatchFinder::Match] Match to encode
        # @param pos [Integer] Position in stream
        # @param bytes [Array<Integer>] All data bytes
        # @return [void]
        def encode_match(match, _pos, _bytes)
          @range_encoder.encode_bit(@match_model, 1)

          # Encode match length
          encode_length(match.length - MATCH_LEN_MIN)

          # Encode match distance
          encode_distance(match.distance - 1)

          @state.update_match
        end

        # Get literal state based on position
        #
        # @param pos [Integer] Current position
        # @param bytes [Array<Integer>] Data bytes
        # @return [Integer] Literal state index
        def get_literal_state(pos, bytes)
          prev_byte = pos.positive? ? bytes[pos - 1] : 0
          ((pos & ((1 << @lp) - 1)) << @lc) + (prev_byte >> (8 - @lc))
        end

        # Encode a literal byte value
        #
        # @param byte [Integer] Byte value
        # @param lit_state [Integer] Literal state
        # @return [void]
        def encode_literal_byte(byte, lit_state)
          models = @literal_models[lit_state % @literal_models.size]
          symbol = 1

          8.downto(1) do |i|
            bit = (byte >> (i - 1)) & 1
            model = models[symbol]
            @range_encoder.encode_bit(model, bit)
            symbol = (symbol << 1) | bit
          end
        end

        # Encode match length
        #
        # @param length [Integer] Length value (already subtracted MIN)
        # @return [void]
        def encode_length(length)
          # Use fixed 8-bit encoding for simplicity
          @range_encoder.encode_direct_bits(length, 8)
        end

        # Encode match distance
        #
        # @param distance [Integer] Distance value (already subtracted 1)
        # @return [void]
        def encode_distance(distance)
          # Use fixed 16-bit encoding for simplicity
          @range_encoder.encode_direct_bits(distance, 16)
        end
      end
    end
  end
end
