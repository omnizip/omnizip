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
require_relative "bit_model"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # SDK-compatible length encoder/decoder
      #
      # This class implements the LZMA SDK's length encoding scheme:
      # - Lengths 0-7: choice=0, 3 bits from low tree
      # - Lengths 8-15: choice=1, choice2=0, 3 bits from mid tree
      # - Lengths 16+: choice=1, choice2=1, 8 bits from high tree
      #
      # Position state is used to select which low/mid tree to use,
      # providing context-dependent compression.
      class LengthCoder
        include Constants

        # Initialize the length coder
        #
        # @param num_pos_states [Integer] Number of position states (1 << pb)
        def initialize(num_pos_states)
          @num_pos_states = num_pos_states
          @choice = BitModel.new
          @choice2 = BitModel.new

          # Low trees: one per position state, 8 symbols each
          # Tree needs 2^(num_bits+1) models: 2^4 = 16 for 3-bit tree
          @low = Array.new(num_pos_states) do
            Array.new(1 << (NUM_LEN_LOW_BITS + 1)) { BitModel.new }
          end

          # Mid trees: one per position state, 8 symbols each
          # Tree needs 2^(num_bits+1) models: 2^4 = 16 for 3-bit tree
          @mid = Array.new(num_pos_states) do
            Array.new(1 << (NUM_LEN_MID_BITS + 1)) { BitModel.new }
          end

          # High tree: shared across all position states, 256 symbols
          # Tree needs 2^(num_bits+1) models: 2^9 = 512 for 8-bit tree
          @high = Array.new(1 << (NUM_LEN_HIGH_BITS + 1)) { BitModel.new }
        end

        # Encode a match length using SDK-compatible encoding
        #
        # @param range_encoder [RangeEncoder] The range encoder
        # @param length [Integer] Length value (already subtracted MATCH_LEN_MIN)
        # @param pos_state [Integer] Position state for tree selection
        # @return [void]
        def encode(range_encoder, length, pos_state)
          trace_encode = ENV.fetch("LZMA_DEBUG_ENCODE", nil) && ENV.fetch("TRACE_LENGTH_CODER", nil)

          if trace_encode
            puts "    [LengthCoder.encode] START: length=#{length}, pos_state=#{pos_state}"
            puts "      @choice.prob=#{@choice.probability} @choice2.prob=#{@choice2.probability}"
          end

          if length < LEN_LOW_SYMBOLS
            # 0-7: Use low tree
            if trace_encode
              puts "      Using LOW tree (length #{length} < #{LEN_LOW_SYMBOLS})"
              puts "      Encoding choice=0 with prob=#{@choice.probability}"
            end
            range_encoder.encode_bit(@choice, 0)
            if trace_encode
              puts "      After choice: @choice.prob=#{@choice.probability}"
            end
            encode_tree(range_encoder, @low[pos_state], length,
                        NUM_LEN_LOW_BITS)
          elsif length < LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS
            # 8-15: Use mid tree
            if trace_encode
              puts "      Using MID tree (length #{length} < #{LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS})"
              puts "      Encoding choice=1 with prob=#{@choice.probability}"
            end
            range_encoder.encode_bit(@choice, 1)
            if trace_encode
              puts "      After choice: @choice.prob=#{@choice.probability}"
              puts "      Encoding choice2=0 with prob=#{@choice2.probability}"
            end
            range_encoder.encode_bit(@choice2, 0)
            if trace_encode
              puts "      After choice2: @choice2.prob=#{@choice2.probability}"
            end
            encode_tree(range_encoder, @mid[pos_state],
                        length - LEN_LOW_SYMBOLS, NUM_LEN_MID_BITS)
          else
            # 16+: Use high tree
            if trace_encode
              puts "      Using HIGH tree (length #{length} >= #{LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS})"
              puts "      Encoding choice=1 with prob=#{@choice.probability}"
            end
            range_encoder.encode_bit(@choice, 1)
            if trace_encode
              puts "      After choice: @choice.prob=#{@choice.probability}"
              puts "      Encoding choice2=1 with prob=#{@choice2.probability}"
            end
            range_encoder.encode_bit(@choice2, 1)
            if trace_encode
              puts "      After choice2: @choice2.prob=#{@choice2.probability}"
            end
            encode_tree(range_encoder, @high,
                        length - LEN_LOW_SYMBOLS - LEN_MID_SYMBOLS,
                        NUM_LEN_HIGH_BITS)
          end

          if trace_encode
            puts "      FINAL @choice.prob=#{@choice.probability} @choice2.prob=#{@choice2.probability}"
            puts "    [LengthCoder.encode] END"
          end
        end

        # Decode a match length using SDK-compatible decoding
        #
        # @param range_decoder [RangeDecoder] The range decoder
        # @param pos_state [Integer] Position state for tree selection
        # @return [Integer] Decoded length value (before adding MATCH_LEN_MIN)
        def decode(range_decoder, pos_state)
          trace_decode = ENV.fetch("LZMA_DEBUG_DISTANCE", nil) && ENV.fetch("TRACE_LENGTH_CODER", nil)

          if trace_decode
            caller_loc = caller_locations(2, 1).first
            puts "    [LengthCoder.decode] START: pos_state=#{pos_state}"
            puts "      self.object_id=#{object_id}"
            puts "      @choice.object_id=#{@choice.object_id} prob=#{@choice.probability}"
            puts "      @choice2.object_id=#{@choice2.object_id} prob=#{@choice2.probability}"
            puts "      Called from: #{caller_loc.label} at #{caller_loc.lineno}"
          end

          choice_bit = range_decoder.decode_bit(@choice)
          if trace_decode
            puts "      Decoded choice=#{choice_bit} with prob=#{@choice.probability}"
            puts "      After choice decode: @choice.prob=#{@choice.probability}"
          end

          if choice_bit.zero?
            # Low tree
            if trace_decode
              puts "      Using LOW tree"
            end
            result = decode_tree(range_decoder, @low[pos_state], NUM_LEN_LOW_BITS)
          elsif range_decoder.decode_bit(@choice2).zero?
            # Mid tree
            if trace_decode
              puts "      Decoded choice2=0 with prob=#{@choice2.probability}"
              puts "      After choice2 decode: @choice2.prob=#{@choice2.probability}"
              puts "      Using MID tree"
            end
            result = LEN_LOW_SYMBOLS +
              decode_tree(range_decoder, @mid[pos_state], NUM_LEN_MID_BITS)
          else
            # High tree
            if trace_decode
              puts "      Decoded choice2=1 with prob=#{@choice2.probability}"
              puts "      After choice2 decode: @choice2.prob=#{@choice2.probability}"
              puts "      Using HIGH tree"
            end
            result = LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS +
              decode_tree(range_decoder, @high, NUM_LEN_HIGH_BITS)
          end

          if trace_decode
            puts "      FINAL @choice.prob=#{@choice.probability} @choice2.prob=#{@choice2.probability}"
            puts "      Result: length_encoded=#{result}"
            puts "    [LengthCoder.decode] END"
          end

          result
        end

        # Reset probability models to initial values
        #
        # Called during state reset (control >= 0xA0) to reset the length
        # coder's probability models. This matches XZ Utils behavior.
        #
        # @return [void]
        def reset_models
          if ENV["TRACE_RESET_MODELS"]
            puts "    [LengthCoder.reset_models] CALLED!"
            puts "      Before reset: @choice.prob=#{@choice.probability} @choice2.prob=#{@choice2.probability}"
            caller_loc = caller_locations(2, 1).first
            puts "      Called from: #{caller_loc.label} at #{caller_loc.path}:#{caller_loc.lineno}"
          end
          @choice.reset
          @choice2.reset

          @low.each do |state_models|
            state_models.each(&:reset)
          end

          @mid.each do |state_models|
            state_models.each(&:reset)
          end

          @high.each(&:reset)
          if ENV["TRACE_RESET_MODELS"]
            puts "      After reset: @choice.prob=#{@choice.probability} @choice2.prob=#{@choice2.probability}"
          end
        end

        private

        # Encode a value using a tree of bit models
        #
        # @param range_encoder [RangeEncoder] The range encoder
        # @param models [Array<BitModel>] Array of bit models for the tree
        # @param symbol [Integer] Symbol to encode
        # @param num_bits [Integer] Number of bits in the tree
        # @return [void]
        def encode_tree(range_encoder, models, symbol, num_bits)
          m = 1
          (num_bits - 1).downto(0) do |i|
            bit = (symbol >> i) & 1
            range_encoder.encode_bit(models[m], bit)
            m = (m << 1) | bit
          end
        end

        # Decode a value using a tree of bit models
        #
        # @param range_decoder [RangeDecoder] The range decoder
        # @param models [Array<BitModel>] Array of bit models for the tree
        # @param num_bits [Integer] Number of bits in the tree
        # @return [Integer] Decoded symbol
        def decode_tree(range_decoder, models, num_bits)
          m = 1
          symbol = 0
          (num_bits - 1).downto(0) do |i|
            bit = range_decoder.decode_bit(models[m])
            m = (m << 1) | bit
            symbol |= (bit << i)
          end
          symbol
        end
      end
    end
  end
end
