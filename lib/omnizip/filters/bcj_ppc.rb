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
    # BCJ filter for PowerPC executables.
    #
    # This filter preprocesses PowerPC machine code by converting
    # relative addresses in B/BL (Branch/Branch and Link) instructions
    # to absolute addresses. PowerPC uses 4-byte aligned instructions
    # with big-endian encoding.
    #
    # The filter improves compression by making branch targets
    # position-independent.
    class BcjPpc < FilterBase
      # PPC B/BL instruction base (0x48000000)
      OPCODE_BASE = 0x48000000

      # Mask for checking B/BL instructions
      OPCODE_MASK = 0xFC000003

      # Expected pattern for B/BL with link bit (0x48000001)
      OPCODE_PATTERN = 0x48000001

      # Size of PPC instruction (4 bytes, big-endian)
      INSTRUCTION_SIZE = 4

      # Offset mask (26-bit offset in instruction)
      OFFSET_MASK = 0x03FFFFFC

      # Encode (preprocess) PowerPC executable data for compression.
      #
      # Scans for B/BL instructions (0x48xxxxxx) and converts relative
      # addresses to absolute addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        return data.dup if data.bytesize < INSTRUCTION_SIZE

        result = data.b
        size = data.bytesize & ~(INSTRUCTION_SIZE - 1)
        i = 0
        pc = position - INSTRUCTION_SIZE

        while i < size
          instruction = extract_uint32_be(result, i)
          pc += INSTRUCTION_SIZE

          # Check for B/BL instruction (0x48xxxxxx with proper flags)
          if (instruction & OPCODE_MASK) == OPCODE_PATTERN
            # Extract 24-bit offset (bits 6-29), sign-extend
            offset = instruction & OFFSET_MASK
            offset = sign_extend_26(offset)

            # Convert to absolute address
            absolute = offset + pc

            # Encode back
            new_instruction = OPCODE_BASE | (absolute & OFFSET_MASK) | 1
            write_uint32_be(result, i, new_instruction)
          end

          i += INSTRUCTION_SIZE
        end

        result
      end

      # Decode (postprocess) PowerPC executable data after decompression.
      #
      # Reverses the encoding by converting absolute addresses back to
      # relative addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        return data.dup if data.bytesize < INSTRUCTION_SIZE

        result = data.b
        size = data.bytesize & ~(INSTRUCTION_SIZE - 1)
        i = 0
        pc = position - INSTRUCTION_SIZE

        while i < size
          instruction = extract_uint32_be(result, i)
          pc += INSTRUCTION_SIZE

          # Check for B/BL instruction
          if (instruction & OPCODE_MASK) == OPCODE_PATTERN
            # Extract absolute address
            absolute = instruction & OFFSET_MASK

            # Convert to relative offset
            offset = absolute - pc

            # Encode back
            new_instruction = OPCODE_BASE | (offset & OFFSET_MASK) | 1
            write_uint32_be(result, i, new_instruction)
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
            name: "BCJ-PPC",
            description: "Branch converter for PowerPC executables",
            architecture: "PowerPC",
            alignment: 4,
            endian: "big",
          }
        end
      end

      private

      # Extract an unsigned 32-bit big-endian integer from data.
      #
      # @param data [String] Binary data
      # @param offset [Integer] Starting position
      # @return [Integer] Unsigned 32-bit integer
      def extract_uint32_be(data, offset)
        bytes = data.byteslice(offset, INSTRUCTION_SIZE).bytes
        (bytes[0] << 24) |
          (bytes[1] << 16) |
          (bytes[2] << 8) |
          bytes[3]
      end

      # Write an unsigned 32-bit big-endian integer to data.
      #
      # @param data [String] Binary data (modified in place)
      # @param offset [Integer] Starting position
      # @param value [Integer] 32-bit integer to write
      # @return [void]
      def write_uint32_be(data, offset, value)
        value &= 0xFFFFFFFF
        data.setbyte(offset, (value >> 24) & 0xFF)
        data.setbyte(offset + 1, (value >> 16) & 0xFF)
        data.setbyte(offset + 2, (value >> 8) & 0xFF)
        data.setbyte(offset + 3, value & 0xFF)
      end

      # Sign-extend a 26-bit value to 32-bit.
      #
      # The offset in PPC B/BL instructions is 26 bits (bits 6-31),
      # but bit 0-1 are always 0 (4-byte aligned).
      #
      # @param value [Integer] 26-bit value
      # @return [Integer] Sign-extended integer
      # rubocop:disable Naming/VariableNumber
      def sign_extend_26(value)
        # rubocop:enable Naming/VariableNumber
        # Check if bit 25 is set (sign bit for 26-bit number)
        if value.anybits?(0x02000000)
          value | 0xFC000000
        else
          value
        end
      end
    end
  end
end
