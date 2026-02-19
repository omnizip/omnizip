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

require_relative "filter_base"

module Omnizip
  module Filters
    # BCJ filter for 32-bit ARM executables.
    #
    # This filter preprocesses ARM machine code by converting relative
    # addresses in BL (Branch and Link - 0xEB) instructions to absolute
    # addresses. ARM uses 4-byte aligned instructions with little-endian
    # encoding.
    #
    # The filter improves compression by making branch targets
    # position-independent. The offset in ARM BL instructions is stored
    # as word offset (divided by 4), and is relative to PC+8.
    class BcjArm < FilterBase
      # ARM BL (Branch and Link) opcode
      OPCODE_BL = 0xEB

      # Size of ARM instruction (4 bytes, little-endian)
      INSTRUCTION_SIZE = 4

      # Offset mask (24-bit offset in BL instruction)
      OFFSET_MASK = 0x00FFFFFF

      # Encode (preprocess) ARM executable data for compression.
      #
      # Scans for BL (0xEB) opcodes and converts relative word offsets
      # to absolute word offsets. ARM branch offset is relative to PC+8.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        return data.dup if data.bytesize < INSTRUCTION_SIZE

        result = data.b
        size = data.bytesize & ~(INSTRUCTION_SIZE - 1)
        i = 0
        # PC starts at position + 4 (as per C implementation)
        pc = position + 4

        while i < size
          # Advance PC to current instruction position
          current_pc = pc + i

          # Check if last byte is 0xEB (BL instruction)
          if result.getbyte(i + 3) == OPCODE_BL
            # Extract full 32-bit instruction value
            instruction = extract_uint32_le(result, i)

            # Calculate word offset from PC
            word_offset = current_pc >> 2

            # Add word offset to instruction value
            instruction += word_offset

            # Mask to 24-bit and combine with opcode
            instruction = (instruction & OFFSET_MASK) | 0xEB000000

            write_uint32_le(result, i, instruction)
          end

          i += INSTRUCTION_SIZE
        end

        result
      end

      # Decode (postprocess) ARM executable data after decompression.
      #
      # Reverses the encoding by converting absolute word offsets back to
      # relative word offsets.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        return data.dup if data.bytesize < INSTRUCTION_SIZE

        result = data.b
        size = data.bytesize & ~(INSTRUCTION_SIZE - 1)
        i = 0
        # PC starts at position + 4 (as per C implementation)
        pc = position + 4

        while i < size
          # Advance PC to current instruction position
          current_pc = pc + i

          # Check if last byte is 0xEB (BL instruction)
          if result.getbyte(i + 3) == OPCODE_BL
            # Extract full 32-bit instruction value
            instruction = extract_uint32_le(result, i)

            # Calculate word offset from PC
            word_offset = current_pc >> 2

            # Subtract word offset from instruction value
            instruction -= word_offset

            # Mask to 24-bit and combine with opcode
            instruction = (instruction & OFFSET_MASK) | 0xEB000000

            write_uint32_le(result, i, instruction)
          end

          i += INSTRUCTION_SIZE
        end

        result
      end

      class << self
        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "BCJ-ARM",
            description: "Branch converter for 32-bit ARM executables",
            architecture: "ARM (32-bit)",
            alignment: 4,
            endian: "little",
          }
        end
      end

      private

      # Extract an unsigned 32-bit little-endian integer from data.
      #
      # @param data [String] Binary data
      # @param offset [Integer] Starting position
      # @return [Integer] Unsigned 32-bit integer
      def extract_uint32_le(data, offset)
        bytes = data.byteslice(offset, INSTRUCTION_SIZE).bytes
        bytes[0] |
          (bytes[1] << 8) |
          (bytes[2] << 16) |
          (bytes[3] << 24)
      end

      # Write an unsigned 32-bit little-endian integer to data.
      #
      # @param data [String] Binary data (modified in place)
      # @param offset [Integer] Starting position
      # @param value [Integer] 32-bit integer to write
      # @return [void]
      def write_uint32_le(data, offset, value)
        value &= 0xFFFFFFFF
        data.setbyte(offset, value & 0xFF)
        data.setbyte(offset + 1, (value >> 8) & 0xFF)
        data.setbyte(offset + 2, (value >> 16) & 0xFF)
        data.setbyte(offset + 3, (value >> 24) & 0xFF)
      end
    end
  end
end
