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
    # BCJ filter for 64-bit ARM (AArch64) executables.
    #
    # This filter preprocesses ARM64 machine code by converting relative
    # addresses in B/BL (0x94) and ADRP (0x90) instructions to absolute
    # addresses. ARM64 uses 4-byte aligned instructions with little-endian
    # encoding.
    #
    # The filter improves compression by making branch targets and
    # page-aligned addresses position-independent.
    class BcjArm64 < FilterBase
      # B/BL instruction base opcode
      OPCODE_B_BL = 0x94000000

      # B/BL instruction mask
      MASK_B_BL = 0xFC000000

      # ADRP instruction base opcode
      OPCODE_ADRP = 0x90000000

      # ADRP instruction mask for variant detection
      MASK_ADRP = 0x9F000000

      # Size of ARM64 instruction (4 bytes)
      INSTRUCTION_SIZE = 4

      # Encode (preprocess) ARM64 executable data for compression.
      #
      # Scans for B/BL (0x94xxxxxx) and ADRP (0x90xxxxxx) instructions
      # and converts relative addresses to absolute addresses.
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
          instruction = extract_uint32_le(result, i)
          pc += INSTRUCTION_SIZE

          # Check for B/BL instruction (0x94xxxxxx)
          if (instruction & MASK_B_BL) == OPCODE_B_BL
            # Extract 26-bit offset, sign-extend, and convert
            offset = sign_extend_26(instruction & 0x03FFFFFF)
            absolute = (offset << 2) + pc
            new_instruction = OPCODE_B_BL | ((absolute >> 2) & 0x03FFFFFF)
            write_uint32_le(result, i, new_instruction)
            i += INSTRUCTION_SIZE
            next
          end

          # Check for ADRP instruction (0x90xxxxxx or 0xB0xxxxxx variants)
          if (instruction & MASK_ADRP) == OPCODE_ADRP
            # Extract immlo (bits [30:29]) and immhi (bits [23:5])
            immlo = (instruction >> 29) & 0x3
            immhi = (instruction >> 5) & 0x7FFFF

            # Combine into 21-bit offset
            offset = (immhi << 2) | immlo

            # Sign-extend 21-bit to full integer
            offset = sign_extend_21(offset)

            # Convert to absolute address (page-aligned, << 12)
            absolute = (offset << 12) + (pc & ~0xFFF)

            # Encode back
            absolute >>= 12
            new_immlo = absolute & 0x3
            new_immhi = (absolute >> 2) & 0x7FFFF

            new_instruction = (instruction & 0x9F00001F) |
              (new_immlo << 29) |
              (new_immhi << 5)
            write_uint32_le(result, i, new_instruction)
          end

          i += INSTRUCTION_SIZE
        end

        result
      end

      # Decode (postprocess) ARM64 executable data after decompression.
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
          instruction = extract_uint32_le(result, i)
          pc += INSTRUCTION_SIZE

          # Check for B/BL instruction
          if (instruction & MASK_B_BL) == OPCODE_B_BL
            # Extract absolute address and convert to relative offset
            absolute = (instruction & 0x03FFFFFF) << 2
            offset = (absolute - pc) >> 2
            new_instruction = OPCODE_B_BL | (offset & 0x03FFFFFF)
            write_uint32_le(result, i, new_instruction)
            i += INSTRUCTION_SIZE
            next
          end

          # Check for ADRP instruction
          if (instruction & MASK_ADRP) == OPCODE_ADRP
            # Extract immlo and immhi
            immlo = (instruction >> 29) & 0x3
            immhi = (instruction >> 5) & 0x7FFFF

            # Combine into absolute page address
            absolute = ((immhi << 2) | immlo) << 12

            # Convert to relative offset
            offset = (absolute - (pc & ~0xFFF)) >> 12

            # Encode back as 21-bit value
            new_immlo = offset & 0x3
            new_immhi = (offset >> 2) & 0x7FFFF

            new_instruction = (instruction & 0x9F00001F) |
              (new_immlo << 29) |
              (new_immhi << 5)
            write_uint32_le(result, i, new_instruction)
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
            name: "BCJ-ARM64",
            description: "Branch converter for 64-bit ARM (AArch64) " \
                         "executables",
            architecture: "ARM64 / AArch64",
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

      # Sign-extend a 26-bit value to 32-bit.
      #
      # @param value [Integer] 26-bit value
      # @return [Integer] Sign-extended integer
      # rubocop:disable Naming/VariableNumber
      def sign_extend_26(value)
        # rubocop:enable Naming/VariableNumber
        if value.anybits?(0x02000000)
          value | 0xFC000000
        else
          value
        end
      end

      # Sign-extend a 21-bit value to 32-bit.
      #
      # @param value [Integer] 21-bit value
      # @return [Integer] Sign-extended integer
      # rubocop:disable Naming/VariableNumber
      def sign_extend_21(value)
        # rubocop:enable Naming/VariableNumber
        if value.anybits?(0x100000)
          value | 0xFFE00000
        else
          value
        end
      end
    end
  end
end
