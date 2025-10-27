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
    # BCJ filter for SPARC executables.
    #
    # This filter preprocesses SPARC machine code by converting relative
    # addresses in CALL and BA (Branch Always) instructions to absolute
    # addresses. SPARC uses 4-byte aligned instructions with big-endian
    # encoding.
    #
    # The filter improves compression by making branch targets
    # position-independent.
    class BcjSparc < FilterBase
      # Size of SPARC instruction (4 bytes, big-endian)
      INSTRUCTION_SIZE = 4

      # Flag constant for address validation
      FLAG = 1 << 22

      # Mask for offset extraction
      OFFSET_MASK = (FLAG << 3) - 1

      # Encode (preprocess) SPARC executable data for compression.
      #
      # Scans for CALL and BA instructions and converts relative addresses
      # to absolute addresses.
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

          # Check for CALL or BA instruction
          # The check is based on specific bit patterns in SPARC ISA
          test_val = instruction + (5 << 29)
          test_val ^= 7 << 29
          test_val += FLAG

          if test_val.nobits?(0 - (FLAG << 1))
            # Extract 22-bit offset (bits 0-21) or 30-bit for CALL
            offset = (instruction << 2) & OFFSET_MASK

            # Convert to absolute address
            absolute = offset + pc

            # Encode back
            new_instruction = (absolute & OFFSET_MASK) >> 2
            new_instruction |= 1 << 30
            write_uint32_be(result, i, new_instruction)
          end

          i += INSTRUCTION_SIZE
        end

        result
      end

      # Decode (postprocess) SPARC executable data after decompression.
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

          # Check for processed instruction pattern
          test_val = instruction + (5 << 29)
          test_val ^= 7 << 29
          test_val += FLAG

          if test_val.nobits?(0 - (FLAG << 1))
            # Extract absolute address
            absolute = (instruction << 2) & OFFSET_MASK

            # Convert to relative offset
            offset = absolute - pc

            # Encode back
            new_instruction = (offset & OFFSET_MASK) >> 2
            new_instruction |= 1 << 30
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
            name: "BCJ-SPARC",
            description: "Branch converter for SPARC executables",
            architecture: "SPARC",
            alignment: 4,
            endian: "big"
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
    end
  end
end
