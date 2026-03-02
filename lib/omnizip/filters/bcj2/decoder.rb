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
      # Uses bulk scanning (C-optimized String#index) to find E8/E9 opcodes
      # and bulk-copies non-opcode byte runs via String#byteslice.
      #
      # @return [String] Decoded binary data
      def decode
        main_data = @streams.main
        main_size = main_data.bytesize
        result = String.new(capacity: main_size + (main_size >> 3),
                            encoding: Encoding::BINARY)
        init_range_decoder

        e8 = "\xE8".b
        e9 = "\xE9".b

        while @main_pos < main_size
          # Find next E8 or E9 using C-optimized String#index
          e8_pos = main_data.index(e8, @main_pos)
          e9_pos = main_data.index(e9, @main_pos)

          next_pos = if e8_pos && e9_pos
                       [e8_pos, e9_pos].min
                     else
                       e8_pos || e9_pos
                     end

          unless next_pos
            # No more opcodes - bulk copy rest
            chunk_len = main_size - @main_pos
            result << main_data.byteslice(@main_pos, chunk_len)
            @ip += chunk_len
            @main_pos = main_size
            break
          end

          # Bulk copy bytes before opcode
          if next_pos > @main_pos
            chunk_len = next_pos - @main_pos
            result << main_data.byteslice(@main_pos, chunk_len)
            @ip += chunk_len
            @main_pos = next_pos
          end

          # Handle E8/E9 opcode
          byte = main_data.getbyte(@main_pos)
          @main_pos += 1

          prob_idx = byte == 0xE8 ? (2 + (@ip & 0xFF)) : 0
          if read_bit(prob_idx)
            # Convertible - read address from call/jump stream
            addr = read_address(byte)
            result << byte
            result << [addr & 0xFFFFFFFF].pack("V")
            @ip += 5
          else
            # Not convertible - just copy byte
            result << byte
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
        # Inlined normalize_range
        if @range < TOP_VALUE
          @range <<= 8
          next_byte = @rc_pos < @streams.rc.bytesize ? @streams.rc.getbyte(@rc_pos) : 0
          @code = (@code << 8) | next_byte
          @rc_pos += 1 if @rc_pos < @streams.rc.bytesize
        end

        prob = @probs[prob_index]
        bound = (@range >> BIT_MODEL_TOTAL_BITS) * prob

        if @code < bound
          @range = bound
          @probs[prob_index] = prob + ((BIT_MODEL_TOTAL - prob) >> MOVE_BITS)
          false
        else
          @range -= bound
          @code -= bound
          @probs[prob_index] = prob - (prob >> MOVE_BITS)
          true
        end
      end

      # Read 32-bit address from call or jump stream.
      #
      # @param opcode [Integer] Opcode (E8 or E9)
      # @return [Integer] Converted address
      def read_address(opcode)
        if opcode == 0xE8
          stream = @streams.call
          stream_pos = @call_pos
        else
          stream = @streams.jump
          stream_pos = @jump_pos
        end

        # Read 4 bytes big-endian
        addr = 0
        4.times do |i|
          break if stream_pos >= stream.bytesize

          addr |= stream.getbyte(stream_pos) << (24 - (i * 8))
          stream_pos += 1
        end

        if opcode == 0xE8
          @call_pos = stream_pos
        else
          @jump_pos = stream_pos
        end

        # Convert back to relative
        addr - (@ip + 5)
      end
    end
  end
end
