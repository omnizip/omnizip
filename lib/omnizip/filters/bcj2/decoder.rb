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
    # Matches the modern 7-Zip SDK Bcj2.c decode loop (v18.06+):
    # - Pre-allocated output buffer (no dynamic growth)
    # - Handles E8 (CALL), E9 (JMP), and JCC (0x0F 0x80-0x8F) opcodes
    # - Probability model: index 0=JCC, 1=E9, 2+prev_byte=E8
    # - Inline range decoder with cached locals
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
      # Matches modern 7-Zip SDK Bcj2Dec_Decode pattern:
      # - Pre-allocated output buffer sized to expected output
      # - Single C-optimized regex scan for E8/E9/JCC opcodes
      # - Direct setbyte writes (no intermediate String allocations)
      # - Opcode written to output before range-coded decision (matches SDK)
      #
      # @param expected_size [Integer, nil] Expected output size for pre-allocation
      # @return [String] Decoded binary data
      # @raise [Omnizip::DecompressionError] If output exceeds buffer capacity when expected_size is nil
      def decode(expected_size = nil)
        main_data = @streams.main
        main_size = main_data.bytesize

        # Pre-allocate output buffer to expected size (C++ SDK: dic is pre-allocated)
        # When expected_size is unknown, use a conservative upper bound
        # Each byte can produce at most 5 bytes (opcode + 4-byte address), but
        # in practice BCJ2 never expands more than 2x due to rarity of convertible opcodes
        out_capacity = expected_size || (main_size * 2)
        result = ("\0" * out_capacity).b
        result_pos = 0

        # Helper to grow buffer if needed (only when expected_size is nil)
        grow_buffer = lambda do |required|
          return if result_pos + required <= result.bytesize

          if expected_size
            raise Omnizip::DecompressionError,
                  "BCJ2 output size (#{result_pos + required}) exceeds expected size (#{expected_size})"
          end

          # Dynamic growth when expected_size is unknown
          new_capacity = [result.bytesize * 2, result_pos + required].max
          new_buf = ("\0" * new_capacity).b
          new_buf[0, result_pos] = result.byteslice(0, result_pos)
          result = new_buf
        end

        # Cache stream references as locals (avoids repeated ivar lookups in hot loop)
        call_data = @streams.call
        jump_data = @streams.jump
        rc_data = @streams.rc
        call_size = call_data.bytesize
        jump_size = jump_data.bytesize
        rc_size = rc_data.bytesize
        call_pos = @call_pos
        jump_pos = @jump_pos
        rc_pos = @rc_pos
        probs = @probs
        ip = @ip

        # Initialize range decoder (read first 5 bytes from RC stream)
        range = 0xFFFFFFFF
        code = 0
        5.times do
          break if rc_pos >= rc_size

          code = ((code << 8) | rc_data.getbyte(rc_pos)) & 0xFFFFFFFF
          rc_pos += 1
        end

        # Regex to find E8, E9, or JCC (0x0F followed by 0x80-0x8F)
        opcode_re = /[\xe8\xe9]|\x0f[\x80-\x8f]/n
        main_pos = @main_pos
        prev_byte = 0

        while main_pos < main_size
          # C-optimized scan for E8, E9, and JCC opcodes
          next_pos = main_data.index(opcode_re, main_pos)

          unless next_pos
            # No more opcodes — bulk copy remaining bytes
            chunk_len = main_size - main_pos
            grow_buffer.call(chunk_len)
            result[result_pos, chunk_len] = main_data.byteslice(main_pos, chunk_len)
            result_pos += chunk_len
            ip += chunk_len
            main_pos = main_size
            break
          end

          # Bulk copy bytes before opcode
          if next_pos > main_pos
            chunk_len = next_pos - main_pos
            grow_buffer.call(chunk_len)
            result[result_pos, chunk_len] = main_data.byteslice(main_pos, chunk_len)
            result_pos += chunk_len
            ip += chunk_len
            main_pos = next_pos
            # Track prev_byte from bulk copy (last byte before opcode in output)
            prev_byte = main_data.getbyte(next_pos - 1)
          end

          byte = main_data.getbyte(main_pos)

          if byte == 0x0F
            # JCC: 0x0F followed by 0x80-0x8F conditional jump
            # Ensure buffer has room for 2 opcode bytes + potential 4 address bytes
            grow_buffer.call(6)
            # Write 0x0F to output (SDK writes opcode bytes before range decision)
            result.setbyte(result_pos, 0x0F)
            result_pos += 1
            ip += 1
            main_pos += 1

            # Read and write the 0x8x second opcode byte
            byte = main_data.getbyte(main_pos)
            result.setbyte(result_pos, byte)
            result_pos += 1
            ip += 1
            main_pos += 1

            prob_idx = 0 # JCC uses probability index 0
            is_call = false
          else
            # E8 (CALL) or E9 (JMP) — write opcode before range decision
            # Ensure buffer has room for 1 opcode byte + potential 4 address bytes
            grow_buffer.call(5)
            result.setbyte(result_pos, byte)
            result_pos += 1
            ip += 1
            main_pos += 1

            if byte == 0xE8
              prob_idx = 2 + prev_byte  # E8 uses prev_byte context (256 models)
              is_call = true
            else
              prob_idx = 1              # E9 uses fixed index 1
              is_call = false
            end
          end

          # Inline range decoder normalization
          if range < TOP_VALUE
            range = (range << 8) & 0xFFFFFFFF
            rc_byte = rc_pos < rc_size ? rc_data.getbyte(rc_pos) : 0
            code = ((code << 8) | rc_byte) & 0xFFFFFFFF
            rc_pos += 1 if rc_pos < rc_size
          end

          prob = probs[prob_idx]
          bound = (range >> BIT_MODEL_TOTAL_BITS) * prob

          if code < bound
            # Bit = 0: not convertible (opcode already written to output)
            range = bound
            probs[prob_idx] = prob + ((BIT_MODEL_TOTAL - prob) >> MOVE_BITS)
            prev_byte = byte
          else
            # Bit = 1: convertible — read 4-byte address from call/jump stream
            range -= bound
            code -= bound
            probs[prob_idx] = prob - (prob >> MOVE_BITS)

            # Read 4 bytes big-endian from call stream (E8) or jump stream (E9/JCC)
            if is_call
              if call_pos + 4 <= call_size
                addr = call_data.byteslice(call_pos, 4).unpack1("N")
                call_pos += 4
              else
                addr = 0
                4.times do |i|
                  break if call_pos >= call_size

                  addr |= call_data.getbyte(call_pos) << (24 - (i * 8))
                  call_pos += 1
                end
              end
            elsif jump_pos + 4 <= jump_size
              addr = jump_data.byteslice(jump_pos, 4).unpack1("N")
              jump_pos += 4
            else
              addr = 0
              4.times do |i|
                break if jump_pos >= jump_size

                addr |= jump_data.getbyte(jump_pos) << (24 - (i * 8))
                jump_pos += 1
              end
            end

            # Convert absolute address to relative (ip already past opcode bytes)
            addr = (addr - (ip + 4)) & 0xFFFFFFFF

            # Write 4-byte little-endian address directly (no pack/Array alloc)
            result.setbyte(result_pos, addr & 0xFF)
            result.setbyte(result_pos + 1, (addr >> 8) & 0xFF)
            result.setbyte(result_pos + 2, (addr >> 16) & 0xFF)
            result.setbyte(result_pos + 3, (addr >> 24) & 0xFF)
            result_pos += 4
            ip += 4
            prev_byte = (addr >> 24) & 0xFF
          end
        end

        # Store final positions back
        @main_pos = main_pos
        @call_pos = call_pos
        @jump_pos = jump_pos
        @rc_pos = rc_pos
        @range = range
        @code = code
        @ip = ip

        # Return exact output (trim if pre-allocated too large)
        result_pos < result.bytesize ? result.byteslice(0, result_pos) : result
      end
    end
  end
end
