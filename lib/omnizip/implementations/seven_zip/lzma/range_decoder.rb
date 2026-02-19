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

# Ported from 7-Zip SDK C/LzmaDec.c
# Direct port of the LZMA SDK range decoder for byte-for-byte compatibility
# with 7-Zip archives.

require_relative "../../../algorithms/lzma/constants"
require_relative "../../../algorithms/lzma/bit_model"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # Range decoder for 7-Zip SDK LZMA decompression
        #
        # This is a direct port of 7-Zip SDK's range decoder implementation
        # from LzmaDec.c for guaranteed compatibility with 7-Zip archives.
        #
        # Reference: /Users/mulgogi/src/external/7-Zip/C/LzmaDec.c
        class RangeDecoder
          include Omnizip::Algorithms::LZMA::Constants

          attr_reader :code

          # Initialize the range decoder
          #
          # @param input_stream [IO] The input stream of encoded bytes
          def initialize(input_stream)
            @stream = input_stream
            @range = 0xFFFFFFFF
            @code = 0
            init_decoder
          end

          # Decode a single bit using a probability model
          #
          # Ported from 7-Zip SDK IF_BIT_0/UPDATE_0/UPDATE_1 macros
          # (LzmaDec.c lines 22-26)
          #
          # SDK pattern:
          #   #define IF_BIT_0(p) ttt = *(p); NORMALIZE; bound = (range >> kNumBitModelTotalBits) * (UInt32)ttt; if (code < bound)
          #   #define UPDATE_0(p) range = bound; *(p) = (CLzmaProb)(ttt + ((kBitModelTotal - ttt) >> kNumMoveBits));
          #   #define UPDATE_1(p) range -= bound; code -= bound; *(p) = (CLzmaProb)(ttt - (ttt >> kNumMoveBits));
          #
          # @param model [BitModel] The probability model for this bit
          # @return [Integer] The decoded bit value (0 or 1)
          def decode_bit(model)
            prob = model.probability

            # NORMALIZE (SDK pattern: normalize BEFORE decoding)
            normalize

            # Calculate bound
            bound = (@range >> 11) * prob

            if @code < bound
              # UPDATE_0: bit is 0
              @range = bound & 0xFFFFFFFF
              new_prob = prob + ((BIT_MODEL_TOTAL - prob) >> MOVE_BITS)
              model.instance_variable_set(:@probability, new_prob)
              0
            else
              # UPDATE_1: bit is 1
              @range = (@range - bound) & 0xFFFFFFFF
              @code = (@code - bound) & 0xFFFFFFFF
              new_prob = prob - (prob >> MOVE_BITS)
              model.instance_variable_set(:@probability, new_prob)
              1
            end
          end

          # Decode bits directly without using probability model
          #
          # @param num_bits [Integer] Number of bits to decode
          # @return [Integer] The decoded value
          def decode_direct_bits(num_bits)
            result = 0
            num_bits.times do
              normalize
              @range >>= 1
              @range &= 0xFFFFFFFF
              @code = (@code - @range) & 0xFFFFFFFF
              bit = (@code >> 31) & 1
              @code = (@code + (@range & (0 - bit))) & 0xFFFFFFFF
              result = (result << 1) | bit
            end
            result
          end

          # Decode bits directly with a base value
          #
          # Used by distance decoder for slots 14+ where we need to
          # build on a base value (2 or 3) iteratively.
          #
          # @param num_bits [Integer] Number of bits to decode
          # @param base [Integer] Base value to start from
          # @return [Integer] The decoded value
          def decode_direct_bits_with_base(num_bits, base)
            result = base
            num_bits.times do
              result = (result << 1) + 1
              normalize
              @range >>= 1
              @range &= 0xFFFFFFFF

              # Check if bit is 1
              bit = @code >= @range ? 1 : 0

              if bit == 1
                @code = (@code - @range) & 0xFFFFFFFF
              else
                result -= 1
              end
            end
            result
          end

          # Update the input stream (for LZMA2 multi-chunk streams)
          #
          # @param new_stream [IO] New input stream
          # @return [void]
          def update_stream(new_stream)
            @stream = new_stream
          end

          # Reset the decoder state (for LZMA2 chunks)
          #
          # @return [void]
          def reset
            @range = 0xFFFFFFFF
            @code = 0
            # Read initial 5 bytes for code
            5.times { @code = ((@code << 8) | read_byte) & 0xFFFFFFFF }
          end

          private

          # Initialize the decoder by reading the first 5 bytes
          #
          # @return [void]
          def init_decoder
            # Read first byte (should be 0 for valid LZMA stream)
            first = read_byte
            raise "Invalid LZMA stream: first byte not 0" unless first.zero?

            # Read 4 bytes for initial code value
            @code = 0
            4.times { @code = ((@code << 8) | read_byte) & 0xFFFFFFFF }
          end

          # Normalize the range when it becomes too small
          #
          # Ported from 7-Zip SDK NORMALIZE macro (LzmaDec.c line 22):
          #   #define NORMALIZE if (range < kTopValue) { range <<= 8; code = (code << 8) | (*buf++); }
          #
          # @return [void]
          def normalize
            while @range < TOP
              @range = (@range << 8) & 0xFFFFFFFF
              @code = ((@code << 8) | read_byte) & 0xFFFFFFFF
            end
          end

          # Read a single byte from the input stream
          #
          # @return [Integer] The byte value (0-255)
          def read_byte
            byte = @stream.getbyte
            if byte.nil?
              raise Omnizip::DecompressionError,
                    "LZMA compressed data exhausted prematurely"
            end

            byte
          end
        end
      end
    end
  end
end
