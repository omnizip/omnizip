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
    # BCJ (Branch/Call/Jump) filter for x86/x64 executables.
    #
    # This filter preprocesses x86 machine code by converting relative
    # addresses in CALL (0xE8) and JMP (0xE9) instructions to absolute
    # addresses. This transformation makes the code more compressible
    # because the addresses become position-independent.
    #
    # The filter is reversible and works on 5-byte boundaries (1-byte
    # opcode + 4-byte address).
    class BcjX86 < FilterBase
      # x86 CALL opcode
      OPCODE_CALL = 0xE8

      # x86 JMP opcode
      OPCODE_JMP = 0xE9

      # Size of x86 address (4 bytes, little-endian)
      ADDRESS_SIZE = 4

      # Instruction size (opcode + address)
      INSTRUCTION_SIZE = 5

      # Encode (preprocess) x86 executable data for compression.
      #
      # Scans for E8/E9 opcodes and converts relative addresses to
      # absolute addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        return data.dup if data.bytesize < INSTRUCTION_SIZE

        result = data.b
        i = 0
        limit = data.bytesize - INSTRUCTION_SIZE

        while i <= limit
          opcode = result.getbyte(i)

          # Check for CALL or JMP instruction
          if [OPCODE_CALL, OPCODE_JMP].include?(opcode)
            # Extract relative offset (4 bytes, little-endian)
            offset = extract_int32_le(result, i + 1)

            # Check if this is a valid relative address
            # Valid addresses have high byte of 0x00 or 0xFF
            if valid_relative_address?(offset)
              # Convert relative to absolute
              # Address is relative to position AFTER instruction
              absolute = offset + position + i + INSTRUCTION_SIZE
              write_int32_le(result, i + 1, absolute)
            end

            # Skip past this instruction
            i += INSTRUCTION_SIZE
          else
            i += 1
          end
        end

        result
      end

      # Decode (postprocess) x86 executable data after decompression.
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
        i = 0
        limit = data.bytesize - INSTRUCTION_SIZE

        while i <= limit
          opcode = result.getbyte(i)

          # Check for CALL or JMP instruction
          if [OPCODE_CALL, OPCODE_JMP].include?(opcode)
            # Extract absolute address (4 bytes, little-endian)
            absolute = extract_int32_le(result, i + 1)

            # Calculate relative offset
            # Offset should be relative to position AFTER instruction
            offset = absolute - (position + i + INSTRUCTION_SIZE)

            # Check if result is a valid relative address
            if valid_relative_address?(offset)
              write_int32_le(result, i + 1, offset)
            end

            # Skip past this instruction
            i += INSTRUCTION_SIZE
          else
            i += 1
          end
        end

        result
      end

      class << self
        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "BCJ-x86",
            description: "Branch/Call/Jump converter for x86/x64 " \
                         "executables",
            architecture: "x86/x64",
          }
        end
      end

      private

      # Extract a signed 32-bit little-endian integer from data.
      #
      # @param data [String] Binary data
      # @param offset [Integer] Starting position
      # @return [Integer] Signed 32-bit integer
      def extract_int32_le(data, offset)
        bytes = data.byteslice(offset, ADDRESS_SIZE).bytes
        value = bytes[0] |
          (bytes[1] << 8) |
          (bytes[2] << 16) |
          (bytes[3] << 24)

        # Convert to signed integer
        value >= 0x80000000 ? value - 0x100000000 : value
      end

      # Write a signed 32-bit little-endian integer to data.
      #
      # @param data [String] Binary data (modified in place)
      # @param offset [Integer] Starting position
      # @param value [Integer] Signed 32-bit integer to write
      # @return [void]
      def write_int32_le(data, offset, value)
        # Convert to unsigned 32-bit
        unsigned = value & 0xFFFFFFFF

        data.setbyte(offset, unsigned & 0xFF)
        data.setbyte(offset + 1, (unsigned >> 8) & 0xFF)
        data.setbyte(offset + 2, (unsigned >> 16) & 0xFF)
        data.setbyte(offset + 3, (unsigned >> 24) & 0xFF)
      end

      # Check if an address value is a valid relative address.
      #
      # Valid relative addresses have a high byte of 0x00 (small positive)
      # or 0xFF (small negative). This indicates they are likely valid
      # relative jumps within executable code.
      #
      # @param value [Integer] Address value to check
      # @return [Boolean] True if valid relative address
      def valid_relative_address?(value)
        unsigned = value & 0xFFFFFFFF
        high_byte = (unsigned >> 24) & 0xFF
        # Only 0x00 (positive) or 0xFF (negative) are valid
        [0x00, 0xFF].include?(high_byte)
      end
    end
  end
end
