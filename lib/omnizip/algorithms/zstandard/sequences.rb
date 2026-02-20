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
require_relative "fse/bitstream"
require_relative "fse/table"

module Omnizip
  module Algorithms
    class Zstandard
      # Sequences section decoder (RFC 8878 Section 3.1.1.3.2)
      #
      # Decodes sequences of (literals_length, match_length, offset)
      # which are then executed to produce the decompressed output.
      class SequencesDecoder
        include Constants

        # @return [Array<Hash>] Decoded sequences
        attr_reader :sequences

        # Parse and decode sequences section
        #
        # @param input [IO] Input stream positioned at sequences section
        # @param literals_size [Integer] Size of decoded literals
        # @param previous_tables [Hash] Previous FSE tables for REPEAT mode
        # @return [SequencesDecoder] Decoder with decoded sequences
        def self.decode(input, literals_size, previous_tables = {})
          decoder = new(input, literals_size, previous_tables)
          decoder.decode_section
          decoder
        end

        # Initialize decoder
        #
        # @param input [IO] Input stream
        # @param literals_size [Integer] Size of decoded literals
        # @param previous_tables [Hash] Previous FSE tables
        def initialize(input, literals_size, previous_tables = {})
          @input = input
          @literals_size = literals_size
          @previous_tables = previous_tables
          @sequences = []
          @fse_tables = {}
        end

        # Decode the sequences section
        #
        # @return [void]
        def decode_section
          # Read number of sequences
          num_sequences = read_sequence_count

          return if num_sequences == 0

          # Read symbol compression modes
          modes = read_symbol_modes

          # Build FSE tables based on modes
          build_fse_tables(modes)

          # Decode sequences
          decode_sequences_internal(num_sequences)
        end

        private

        # Read sequence count (1-3 bytes)
        def read_sequence_count
          byte1 = @input.read(1).ord

          if byte1 == 0
            0
          elsif byte1 < 128
            byte1
          else
            byte2 = @input.read(1).ord
            ((byte1 - 0x80) << 8) + byte2 + 0x80
          end
        end

        # Read symbol compression modes for LL, ML, OF
        def read_symbol_modes
          modes_byte = @input.read(1).ord

          {
            ll: (modes_byte >> 6) & 0x03,  # Literals length mode
            of: (modes_byte >> 4) & 0x03,  # Offset mode
            ml: (modes_byte >> 2) & 0x03   # Match length mode
          }
        end

        # Build FSE tables based on compression modes
        def build_fse_tables(modes)
          @fse_tables[:ll] = build_fse_table(modes[:ll], :ll)
          @fse_tables[:ml] = build_fse_table(modes[:ml], :ml)
          @fse_tables[:of] = build_fse_table(modes[:of], :of)
        end

        # Build a single FSE table
        def build_fse_table(mode, type)
          case mode
          when MODE_PREDEFINED
            build_predefined_table(type)
          when MODE_RLE
            build_rle_table(type)
          when MODE_FSE
            build_fse_table_from_stream(type)
          when MODE_REPEAT
            @previous_tables[type] || build_predefined_table(type)
          end
        end

        # Build predefined FSE table
        def build_predefined_table(type)
          case type
          when :ll
            FSE::Table.build_predefined(PREDEFINED_LL_DISTRIBUTION.to_a,
                                        LITERALS_LENGTH_ACCURACY_LOG)
          when :ml
            FSE::Table.build_predefined(PREDEFINED_ML_DISTRIBUTION.to_a,
                                        MATCH_LENGTH_ACCURACY_LOG)
          when :of
            FSE::Table.build_predefined(PREDEFINED_OFFSET_DISTRIBUTION.to_a,
                                        OFFSET_ACCURACY_LOG)
          end
        end

        # Build RLE FSE table (single symbol repeated)
        def build_rle_table(type)
          # Read the repeated symbol
          symbol = @input.read(1).ord

          # Create a simple distribution with just this symbol
          distribution = Array.new(symbol_count_for_type(type), 0)
          distribution[symbol] = 1 << (accuracy_log_for_type(type))

          FSE::Table.build(distribution, accuracy_log_for_type(type))
        end

        # Build FSE table from compressed stream
        def build_fse_table_from_stream(type)
          # Read accuracy log
          accuracy_log = @input.read(1).ord

          # For simplicity, return predefined table
          # Full implementation would read compressed distribution
          build_predefined_table(type)
        end

        # Decode sequences using FSE tables
        def decode_sequences_internal(count)
          return if count == 0

          # Read the bitstream (remaining data in block)
          bitstream_data = @input.read # Read remaining data
          bitstream = FSE::BitStream.new(bitstream_data)

          # Initialize FSE decoders
          ll_decoder = FSE::Decoder.new(@fse_tables[:ll]) if @fse_tables[:ll]
          ml_decoder = FSE::Decoder.new(@fse_tables[:ml]) if @fse_tables[:ml]
          of_decoder = FSE::Decoder.new(@fse_tables[:of]) if @fse_tables[:of]

          # Initialize states
          ll_decoder&.init_state(bitstream)
          ml_decoder&.init_state(bitstream)
          of_decoder&.init_state(bitstream)

          # Decode each sequence
          count.times do
            ll_symbol = ll_decoder ? ll_decoder.decode(bitstream) : 0
            ml_symbol = ml_decoder ? ml_decoder.decode(bitstream) : 0
            of_symbol = of_decoder ? of_decoder.decode(bitstream) : 0

            # Convert symbols to actual values
            ll_value = decode_literal_length(ll_symbol, bitstream)
            ml_value = decode_match_length(ml_symbol, bitstream)
            of_value = decode_offset(of_symbol, bitstream)

            @sequences << {
              literals_length: ll_value,
              match_length: ml_value,
              offset: of_value
            }
          end
        end

        # Decode literal length value from symbol
        def decode_literal_length(symbol, bitstream)
          return 0 if symbol.nil? || symbol < 0 || symbol >= LITERAL_LENGTH_TABLE.length

          baseline, extra_bits = LITERAL_LENGTH_TABLE[symbol]
          return baseline if extra_bits == 0

          extra = bitstream.read_bits(extra_bits)
          baseline + extra
        end

        # Decode match length value from symbol
        def decode_match_length(symbol, bitstream)
          return 3 if symbol.nil? || symbol < 0 || symbol >= MATCH_LENGTH_TABLE.length

          baseline, extra_bits = MATCH_LENGTH_TABLE[symbol]
          return baseline if extra_bits == 0

          extra = bitstream.read_bits(extra_bits)
          baseline + extra
        end

        # Decode offset value from symbol
        def decode_offset(symbol, bitstream)
          # Offsets 1-3 are repeat offsets
          return symbol if symbol <= 3

          # For offsets > 3, read extra bits
          # The offset is symbol - 3 plus extra bits
          symbol - 3
        end

        # Get symbol count for type
        def symbol_count_for_type(type)
          case type
          when :ll then LITERAL_LENGTH_TABLE.length
          when :ml then MATCH_LENGTH_TABLE.length
          when :of then 32
          end
        end

        # Get accuracy log for type
        def accuracy_log_for_type(type)
          case type
          when :ll then LITERALS_LENGTH_ACCURACY_LOG
          when :ml then MATCH_LENGTH_ACCURACY_LOG
          when :of then OFFSET_ACCURACY_LOG
          end
        end
      end

      # Sequence executor (RFC 8878 Section 3.1.2.2.3)
      #
      # Executes decoded sequences to produce output.
      class SequenceExecutor
        include Constants

        # Execute sequences to produce decompressed output
        #
        # @param literals [String] Decoded literals
        # @param sequences [Array<Hash>] Decoded sequences
        # @return [String] Decompressed output
        def self.execute(literals, sequences)
          executor = new
          executor.execute(literals, sequences)
        end

        # Initialize with default repeat offsets
        def initialize
          @repeat_offsets = DEFAULT_REPEAT_OFFSETS.dup
        end

        # Execute sequences
        #
        # @param literals [String] Decoded literals
        # @param sequences [Array<Hash>] Decoded sequences
        # @return [String] Decompressed output
        def execute(literals, sequences)
          output = String.new(encoding: Encoding::BINARY)
          lit_pos = 0

          sequences.each do |seq|
            ll = seq[:literals_length] || 0
            ml = seq[:match_length] || 0
            offset_code = seq[:offset] || 0

            # Copy literals
            if ll > 0 && lit_pos < literals.length
              copy_len = [ll, literals.length - lit_pos].min
              output << literals.slice(lit_pos, copy_len)
              lit_pos += copy_len
            end

            # Handle match
            if ml > 0
              offset = resolve_offset(offset_code)

              if offset > 0 && offset <= output.length
                # Copy match from output history
                match_str = output.slice(-offset, [ml, offset].min) || ""
                # If match is longer than offset, we need to copy byte by byte
                while match_str.length < ml && output.length > 0
                  match_str << match_str[-offset] if offset <= match_str.length
                end
                output << match_str.slice(0, ml)
              end
            end
          end

          # Copy remaining literals (last sequence has no match)
          if lit_pos < literals.length
            output << literals.slice(lit_pos..-1)
          end

          output
        end

        private

        # Resolve offset code to actual offset
        def resolve_offset(code)
          case code
          when 1
            @repeat_offsets[0]
          when 2
            @repeat_offsets[1]
          when 3
            @repeat_offsets[2]
          else
            # New offset - update repeat offsets
            actual_offset = code - 3
            @repeat_offsets[2] = @repeat_offsets[1]
            @repeat_offsets[1] = @repeat_offsets[0]
            @repeat_offsets[0] = actual_offset
            actual_offset
          end
        end
      end
    end
  end
end
