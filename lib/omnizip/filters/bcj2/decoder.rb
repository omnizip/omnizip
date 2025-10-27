# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

require_relative "constants"
require_relative "stream_data"

module Omnizip
  module Filters
    # BCJ2 decoder - reconstructs original data from 4 streams.
    #
    # Combines:
    # - Main stream (non-convertible bytes)
    # - Call stream (CALL/E8 addresses)
    # - Jump stream (JUMP/E9 addresses)
    # - RC stream (range coder probability data)
    class Bcj2Decoder
      include Bcj2Constants

      attr_reader :ip

      # Initialize decoder.
      #
      # @param streams [Bcj2StreamData] The 4 input streams
      # @param position [Integer] Starting instruction pointer
      def initialize(streams, position = 0)
        @streams = streams
        @ip = position
        @range = 0
        @code = 0
        @probs = Array.new(NUM_PROBS, INITIAL_PROB)

        # Stream positions
        @main_pos = 0
        @call_pos = 0
        @jump_pos = 0
        @rc_pos = 0
      end

      # Decode 4 streams back to original data.
      #
      # @return [String] Decoded binary data
      def decode
        result = String.new(encoding: Encoding::BINARY)
        init_range_decoder

        loop do
          break if @main_pos >= @streams.main.bytesize

          byte = @streams.main.getbyte(@main_pos)
          @main_pos += 1

          # Check for CALL (E8) or JUMP (E9) opcodes
          if [OPCODE_CALL, OPCODE_JUMP].include?(byte)
            # Use range decoder to determine if convertible
            if read_bit(get_prob_index(byte))
              # Convertible - read address from call/jump stream
              addr = read_address(byte)
              result << byte.chr(Encoding::BINARY)
              result << encode_int32_le(addr)
              @ip += 5
            else
              # Not convertible - just copy byte
              result << byte.chr(Encoding::BINARY)
              @ip += 1
            end
          else
            # Regular byte - just copy
            result << byte.chr(Encoding::BINARY)
            @ip += 1
          end
        end

        result
      end

      private

      # Initialize range decoder by reading first 5 bytes from RC stream.
      #
      # @return [void]
      def init_range_decoder
        @range = 0xFFFFFFFF
        @code = 0

        5.times do
          break if @rc_pos >= @streams.rc.bytesize

          @code = (@code << 8) | @streams.rc.getbyte(@rc_pos)
          @rc_pos += 1
        end
      end

      # Read a single bit from range coder.
      #
      # @param prob_index [Integer] Probability model index
      # @return [Boolean] Decoded bit (true = 1, false = 0)
      def read_bit(prob_index) # rubocop:disable Naming/PredicateMethod
        normalize_range

        prob = @probs[prob_index]
        bound = (@range >> BIT_MODEL_TOTAL_BITS) * prob

        if @code < bound
          # Bit is 0
          @range = bound
          @probs[prob_index] += (BIT_MODEL_TOTAL - prob) >> MOVE_BITS
          false
        else
          # Bit is 1
          @range -= bound
          @code -= bound
          @probs[prob_index] -= prob >> MOVE_BITS
          true
        end
      end

      # Normalize range decoder if needed.
      #
      # @return [void]
      def normalize_range
        while @range < TOP_VALUE
          @range <<= 8
          next_byte = if @rc_pos < @streams.rc.bytesize
                        @streams.rc.getbyte(@rc_pos)
                      else
                        0
                      end
          @code = (@code << 8) | next_byte
          @rc_pos += 1 if @rc_pos < @streams.rc.bytesize
        end
      end

      # Get probability model index for a byte.
      #
      # @param byte [Integer] Byte value
      # @return [Integer] Probability model index
      def get_prob_index(byte)
        # Use byte-specific model for E8, general model for E9
        byte == OPCODE_CALL ? (2 + (@ip & 0xFF)) : 0
      end

      # Read 32-bit address from call or jump stream.
      #
      # @param opcode [Integer] Opcode (E8 or E9)
      # @return [Integer] Converted address
      def read_address(opcode)
        stream_pos = opcode == OPCODE_CALL ? @call_pos : @jump_pos
        stream = opcode == OPCODE_CALL ? @streams.call : @streams.jump

        # Read 4 bytes (big-endian in stream, stored as absolute)
        addr = 0
        4.times do |i|
          break if stream_pos >= stream.bytesize

          addr |= stream.getbyte(stream_pos) << (24 - (i * 8))
          stream_pos += 1
        end

        # Update stream position
        if opcode == OPCODE_CALL
          @call_pos = stream_pos
        else
          @jump_pos = stream_pos
        end

        # Convert back to relative
        addr - (@ip + 5)
      end

      # Encode 32-bit integer as little-endian bytes.
      #
      # @param value [Integer] Value to encode
      # @return [String] 4-byte string
      def encode_int32_le(value)
        unsigned = value & 0xFFFFFFFF
        [
          unsigned & 0xFF,
          (unsigned >> 8) & 0xFF,
          (unsigned >> 16) & 0xFF,
          (unsigned >> 24) & 0xFF
        ].pack("C*")
      end
    end
  end
end
