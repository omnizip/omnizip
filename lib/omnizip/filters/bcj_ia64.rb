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
    # BCJ filter for IA-64 (Itanium) executables.
    #
    # This filter preprocesses Itanium machine code by converting
    # relative addresses in branch instructions. IA-64 uses a complex
    # VLIW (Very Long Instruction Word) architecture with 16-byte
    # instruction bundles containing 3 instructions plus a template.
    #
    # The filter improves compression by making branch targets
    # position-independent.
    class BcjIa64 < FilterBase
      # Size of IA-64 instruction bundle (16 bytes, little-endian)
      BUNDLE_SIZE = 16

      # Template lookup table for instruction slot positions
      # Each bit pattern indicates which slots may contain branch instr
      TEMPLATE_MASKS = 0x334B0000

      # Encode (preprocess) IA-64 executable data for compression.
      #
      # Scans 16-byte instruction bundles for branch instructions and
      # converts relative addresses to absolute addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        return data.dup if data.bytesize < BUNDLE_SIZE

        result = data.b
        size = data.bytesize & ~(BUNDLE_SIZE - 1)
        i = 0
        pc = (position >> 4) << 1

        while i < size
          # Check template byte for slots with potential branches
          template = result.getbyte(i) & 0x1E
          mask = (TEMPLATE_MASKS >> template) & 3
          pc += 2

          i += BUNDLE_SIZE
          next if mask.zero?

          # Process each marked slot
          process_bundle_slots(result, i - BUNDLE_SIZE, mask, pc, true)
        end

        result
      end

      # Decode (postprocess) IA-64 executable data after decompression.
      #
      # Reverses the encoding by converting absolute addresses back to
      # relative addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        return data.dup if data.bytesize < BUNDLE_SIZE

        result = data.b
        size = data.bytesize & ~(BUNDLE_SIZE - 1)
        i = 0
        pc = (position >> 4) << 1

        while i < size
          # Check template byte for slots with potential branches
          template = result.getbyte(i) & 0x1E
          mask = (TEMPLATE_MASKS >> template) & 3
          pc += 2

          i += BUNDLE_SIZE
          next if mask.zero?

          # Process each marked slot
          process_bundle_slots(result, i - BUNDLE_SIZE, mask, pc, false)
        end

        result
      end

      class << self
        # Get metadata about this filter.
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "BCJ-IA64",
            description: "Branch converter for IA-64 (Itanium) " \
                         "executables",
            architecture: "IA-64 / Itanium",
            alignment: 16,
            endian: "little",
            complexity: "high"
          }
        end
      end

      private

      # Process instruction slots within a bundle.
      #
      # @param data [String] Binary data
      # @param offset [Integer] Bundle offset
      # @param mask [Integer] Slot mask
      # @param pc [Integer] Program counter
      # @param encoding [Boolean] True for encoding, false for decoding
      # @return [void]
      # rubocop:disable Naming/MethodParameterName
      def process_bundle_slots(data, offset, mask, pc, encoding)
        # rubocop:enable Naming/MethodParameterName
        slot_offset = 0

        3.times do
          break if mask.zero?

          if mask.anybits?(1)
            process_slot(data, offset + 1 + slot_offset, pc, encoding)
          end

          mask >>= 1
          slot_offset += 5
        end
      end

      # Process a single instruction slot.
      #
      # @param data [String] Binary data
      # @param offset [Integer] Slot offset within bundle
      # @param pc [Integer] Program counter
      # @param encoding [Boolean] True for encoding, false for decoding
      # @return [void]
      # rubocop:disable Naming/MethodParameterName
      def process_slot(data, offset, pc, encoding)
        # rubocop:enable Naming/MethodParameterName
        # Extract slot data (5 bytes forming a 41-bit instruction)
        bytes = data.byteslice(offset, 5).bytes
        instruction = bytes[0] |
                      (bytes[1] << 8) |
                      (bytes[2] << 16) |
                      (bytes[3] << 24) |
                      (bytes[4] << 32)

        # Check if this is a branch instruction
        # Opcode check: bits 37-40 should be 0x5 (B-type instruction)
        opcode = (instruction >> 37) & 0xF
        return unless opcode == 5

        # Extract 25-bit target address from bits 13-37
        target = (instruction >> 13) & 0x1FFFFFF

        # Apply address conversion
        new_target = if encoding
                       # Convert relative to absolute
                       (target + pc) & 0x1FFFFFF
                     else
                       # Convert absolute to relative
                       (target - pc) & 0x1FFFFFF
                     end

        # Reconstruct instruction with new target
        instruction = (instruction & ~(0x1FFFFFF << 13)) |
                      (new_target << 13)

        # Write back the modified instruction
        data.setbyte(offset, instruction & 0xFF)
        data.setbyte(offset + 1, (instruction >> 8) & 0xFF)
        data.setbyte(offset + 2, (instruction >> 16) & 0xFF)
        data.setbyte(offset + 3, (instruction >> 24) & 0xFF)
        data.setbyte(offset + 4, (instruction >> 32) & 0xFF)
      end
    end
  end
end
