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

require_relative "../../../algorithms/lzma/constants"
require_relative "range_decoder" # Use 7-Zip SDK range decoder (not XZ Utils)
require_relative "../../../algorithms/lzma/bit_model"
require_relative "../../../algorithms/lzma/length_coder"
require_relative "../../../algorithms/lzma/distance_coder"
require_relative "state_machine"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # 7-Zip SDK compatible LZMA decoder.
        #
        # This decoder is designed to decode data encoded by the 7-Zip SDK encoder.
        # Uses the same shared infrastructure (RangeDecoder, LengthCoder, DistanceCoder)
        # to ensure model layout compatibility with the encoder.
        class Decoder
          include Omnizip::Algorithms::LZMA::Constants

          attr_reader :lc, :lp, :pb, :dict_size, :uncompressed_size

          # Initialize 7-Zip LZMA decoder
          #
          # @param input [IO] Input stream with LZMA compressed data
          # @param options [Hash] Decoding options
          # @option options [Boolean] :raw_mode Skip header parsing (for LZMA2)
          # @option options [Integer] :lc Literal context bits
          # @option options [Integer] :lp Literal position bits
          # @option options [Integer] :pb Position bits
          # @option options [Integer] :dict_size Dictionary size
          def initialize(input, options = {})
            @input = input
            @raw_mode = options.fetch(:raw_mode, false)

            if @raw_mode
              @lc = options[:lc] || 3
              @lp = options[:lp] || 0
              @pb = options[:pb] || 2
              @dict_size = options[:dict_size] || (1 << 16)
              @uncompressed_size = options[:uncompressed_size]
            else
              parse_header
            end

            init_decoder
          end

          # Decode LZMA stream
          #
          # @param output [IO, nil] Output stream (if nil, returns String)
          # @param preserve_dict [Boolean] Preserve dictionary for chunked decoding
          # @return [String, Integer] Decompressed data or bytes written
          def decode_stream(output = nil, preserve_dict: false)
            @output_buffer = []
            @dictionary = Array.new(@dict_size, 0) unless preserve_dict && @dictionary
            @dict_pos = 0
            @dict_full = false

            # Initialize range decoder (7-Zip SDK version)
            @range_decoder = RangeDecoder.new(@input)

            # Main decode loop
            loop do
              break if reached_end?

              # Track if we were using EOPM before decoding
              was_using_eopm = @allow_eopm

              decode_symbol

              # If we were using EOPM and now we're not, EOS was detected
              break if was_using_eopm && !@allow_eopm
            end

            result = @output_buffer.pack("C*").force_encoding(Encoding::BINARY)

            if output
              output.write(result)
              result.bytesize
            else
              result
            end
          end

          # Reset decoder state for new chunk (LZMA2)
          def reset(new_lc: nil, new_lp: nil, new_pb: nil, preserve_dict: false)
            @lc = new_lc if new_lc
            @lp = new_lp if new_lp
            @pb = new_pb if new_pb

            unless preserve_dict
              @dictionary = Array.new(@dict_size, 0)
              @dict_pos = 0
              @dict_full = false
            end

            init_decoder
          end

          # Set new input stream (LZMA2)
          def set_input(new_input)
            @input = new_input
          end

          # Set uncompressed size (LZMA2)
          def set_uncompressed_size(size, allow_eopm: true)
            @uncompressed_size = size
            @allow_eopm = allow_eopm
          end

          private

          # Parse LZMA header
          def parse_header
            props = @input.getbyte
            raise "Invalid LZMA header: missing properties" unless props

            @lc = props % 9
            rem = props / 9
            @lp = rem % 5
            @pb = rem / 5

            raise "Invalid LZMA properties: pb=#{@pb} > 4" if @pb > 4

            @dict_size = 0
            4.times do |i|
              byte = @input.getbyte
              raise "Invalid LZMA header: missing dictionary size" unless byte

              @dict_size |= (byte << (i * 8))
            end

            @dict_size = [@dict_size, 1].max

            @uncompressed_size = 0
            8.times do |i|
              byte = @input.getbyte
              raise "Invalid LZMA header: missing uncompressed size" unless byte

              @uncompressed_size |= (byte * (1 << (i * 8)))
            end

            @allow_eopm = (@uncompressed_size == 0xFFFFFFFFFFFFFFFF)
          end

          # Initialize decoder state
          def init_decoder
            @state = StateMachine.new
            @reps = [0, 0, 0, 0]

            # Calculate literal_mask using XZ Utils formula
            # literal_mask = (UINT32_C(0x100) << (lp)) - (UINT32_C(0x100) >> (lc))
            @literal_mask = (0x100 << @lp) - (0x100 >> @lc)

            # Initialize literal models using same layout as encoder
            # max_context = literal_mask
            # max_base_offset = 3 * (max_context << lc)
            # max_model_index = max_base_offset + 0x300
            max_context = @literal_mask
            max_base_offset = 3 * (max_context << @lc)
            max_model_index = max_base_offset + 0x300

            @literal_models = Array.new(max_model_index + 1) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end

            # Initialize probability models using same layout as encoder
            num_pos_states = 1 << @pb
            @is_match_models = Array.new(NUM_STATES * num_pos_states) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep_models = Array.new(NUM_STATES) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep0_models = Array.new(NUM_STATES) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep1_models = Array.new(NUM_STATES) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep2_models = Array.new(NUM_STATES) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end
            @is_rep0_long_models = Array.new(NUM_STATES * num_pos_states) do
              Omnizip::Algorithms::LZMA::BitModel.new
            end

            # Use shared LengthCoder and DistanceCoder (they have decode methods)
            @length_coder = Omnizip::Algorithms::LZMA::LengthCoder.new(num_pos_states)
            @rep_length_coder = Omnizip::Algorithms::LZMA::LengthCoder.new(num_pos_states)
            @distance_coder = Omnizip::Algorithms::LZMA::DistanceCoder.new(NUM_LEN_TO_POS_STATES)

            @output_count = 0
          end

          # Check if we've reached end of stream
          def reached_end?
            if @allow_eopm
              false
            else
              @output_count >= @uncompressed_size
            end
          end

          # Decode one symbol
          def decode_symbol
            pos_state = @output_count & ((1 << @pb) - 1)

            # Decode is_match using same model layout as encoder
            model_index = (@state.value * (1 << @pb)) + pos_state
            is_match = @range_decoder.decode_bit(@is_match_models[model_index])

            if is_match.zero?
              decode_literal
            else
              decode_match(pos_state)
            end
          end

          # Decode a literal byte
          def decode_literal
            prev_byte = @dict_pos.positive? ? @dictionary[@dict_pos - 1] : 0

            # Calculate base_offset using XZ Utils formula (same as encoder)
            # context = (((pos << 8) + prev_byte) & literal_mask)
            # base_offset = 3 * (context << lc)
            context = (((@output_count << 8) + prev_byte) & @literal_mask)
            base_offset = 3 * (context << @lc)

            symbol = 1

            if @state.use_matched_literal?
              # Matched literal: use match byte from dictionary
              #
              # XZ Utils decoder pattern (from range_decoder.h rc_matched_literal):
              # - symbol starts at 1
              # - match_byte is shifted FIRST, then match_bit extracted
              # - subcoder_index = offset + match_bit + symbol (symbol not shifted)
              # - offset updated: if bit 0: offset &= ~match_bit, if bit 1: offset &= match_bit
              # - loop 8 times
              #
              match_byte_val = get_byte_from_dict(@reps[0])
              offset = 0x100
              symbol = 1 # XZ Utils starts at 1, not 0x100

              8.times do
                # Shift match_byte FIRST (matches XZ Utils decoder)
                match_byte_val <<= 1

                # Get match_bit from shifted value
                match_bit = match_byte_val & offset

                # Calculate subcoder index (XZ Utils: offset + match_bit + symbol)
                model_idx = base_offset + offset + match_bit + symbol

                # Decode bit
                bit = @range_decoder.decode_bit(@literal_models[model_idx])

                # Update symbol and offset based on decoded bit
                if bit.zero?
                  symbol <<= 1
                  offset &= ~match_bit
                else
                  symbol = (symbol << 1) + 1
                  offset &= match_bit
                end
              end

            else
              # Normal (unmatched) literal
              8.times do
                bit = @range_decoder.decode_bit(@literal_models[base_offset + symbol])
                symbol = (symbol << 1) | bit
              end
            end
            byte = symbol & 0xFF

            put_byte_to_dict(byte)
            @output_buffer << byte
            @output_count += 1
            @state.update_literal
          end

          # Decode a match
          def decode_match(pos_state)
            is_rep = @range_decoder.decode_bit(@is_rep_models[@state.value])

            if is_rep.zero?
              # Simple match
              len = @length_coder.decode(@range_decoder, pos_state) + MATCH_LEN_MIN
              @state.update_match

              # Decode distance
              len_state = [len - MATCH_LEN_MIN, NUM_LEN_TO_POS_STATES - 1].min
              distance = @distance_coder.decode(@range_decoder, len_state)

              # Check for EOPM (distance = 0xFFFFFFFF means end marker)
              if distance == 0xFFFFFFFF
                @allow_eopm = false
                return
              end

              # Decoder returns distance before +1, so add 1 to get actual distance
              distance += 1

              raise "Invalid distance: #{distance}" if distance >= @dict_size && @dict_full

              # Update reps
              @reps[3] = @reps[2]
              @reps[2] = @reps[1]
              @reps[1] = @reps[0]
              @reps[0] = distance
            else
              # Repeated match
              len, distance = decode_rep_match(pos_state)
            end

            # Copy from dictionary
            len.times do
              byte = get_byte_from_dict(distance)
              put_byte_to_dict(byte.ord)
              @output_buffer << byte
              @output_count += 1
            end
          end

          # Decode repeated match
          def decode_rep_match(pos_state)
            if @range_decoder.decode_bit(@is_rep0_models[@state.value]).zero?
              # Rep0
              if @range_decoder.decode_bit(
                @is_rep0_long_models[(@state.value * (1 << @pb)) + pos_state],
              ).zero?
                # Short rep (length 1)
                @state.update_short_rep
                return [1, @reps[0]]
              end

              len = @rep_length_coder.decode(@range_decoder, pos_state) + MATCH_LEN_MIN
              @state.update_rep
              return [len, @reps[0]]
            end

            if @range_decoder.decode_bit(@is_rep1_models[@state.value]).zero?
              # Rep1
              len = @rep_length_coder.decode(@range_decoder, pos_state) + MATCH_LEN_MIN
              distance = @reps[1]
              @reps[1] = @reps[0]
              @reps[0] = distance
              @state.update_rep
              return [len, distance]
            end

            if @range_decoder.decode_bit(@is_rep2_models[@state.value]).zero?
              # Rep2
              len = @rep_length_coder.decode(@range_decoder, pos_state) + MATCH_LEN_MIN
              distance = @reps[2]
              @reps[2] = @reps[1]
              @reps[1] = @reps[0]
              @reps[0] = distance
              @state.update_rep
              return [len, distance]
            end

            # Rep3
            len = @rep_length_coder.decode(@range_decoder, pos_state) + MATCH_LEN_MIN
            distance = @reps[3]
            @reps[3] = @reps[2]
            @reps[2] = @reps[1]
            @reps[1] = @reps[0]
            @reps[0] = distance
            @state.update_rep
            [len, distance]
          end

          # Get byte from dictionary at distance
          # Distance 1 = most recent byte = position dict_pos - 1
          # Distance N = position dict_pos - N
          def get_byte_from_dict(distance)
            if distance > @dict_pos && !@dict_full
              0
            else
              # Use positive modulo to handle negative numbers correctly
              pos = (@dict_pos - distance) % @dict_size
              @dictionary[pos]
            end
          end

          # Put byte to dictionary
          def put_byte_to_dict(byte)
            @dictionary[@dict_pos] = byte
            @dict_pos = (@dict_pos + 1) % @dict_size
            @dict_full = true if @dict_pos.zero?
          end
        end
      end
    end
  end
end
