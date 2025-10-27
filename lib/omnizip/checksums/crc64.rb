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

require_relative "crc_base"

module Omnizip
  module Checksums
    # CRC64 checksum implementation using ECMA-182 polynomial.
    #
    # This implementation uses the ECMA-182 polynomial for CRC64 calculation
    # as used in the XZ file format and 7-Zip archives. This is the standard
    # 64-bit CRC polynomial for data integrity verification in compressed
    # archives.
    #
    # The algorithm uses a 256-entry pre-computed lookup table with 64-bit
    # values for efficient O(1) per-byte processing.
    #
    # Polynomial: 0xC96C5795D7870F42 (ECMA-182)
    # Initial value: 0xFFFFFFFFFFFFFFFF
    # Final XOR: 0xFFFFFFFFFFFFFFFF
    # Bit width: 64
    #
    # @example One-shot calculation
    #   checksum = Omnizip::Checksums::Crc64.calculate("123456789")
    #   # => 0x995DC9BBDF1939FA
    #
    # @example Incremental calculation
    #   crc = Omnizip::Checksums::Crc64.new
    #   crc.update("Hello, ")
    #   crc.update("world!")
    #   result = crc.finalize
    class Crc64 < CrcBase
      # ECMA-182 polynomial (reversed representation)
      # This is the standard polynomial used in XZ format
      POLYNOMIAL = 0xC96C5795D7870F42

      # 64-bit mask for truncating values
      MASK_64 = 0xFFFFFFFFFFFFFFFF

      # Pre-computed lookup table for CRC64 calculation
      # Generated using the ECMA-182 polynomial
      # This table is computed once at class load time for performance
      TABLE = generate_table(POLYNOMIAL, 64).freeze

      # Process a single byte through the CRC64 algorithm.
      #
      # Uses the lookup table for efficient computation:
      # new_crc = (old_crc >> 8) ^ table[(old_crc ^ byte) & 0xFF]
      #
      # @param crc [Integer] current CRC value
      # @param byte [Integer] byte to process (0-255)
      # @return [Integer] updated CRC value
      def process_byte(crc, byte)
        index = (crc ^ byte) & 0xFF
        (crc >> 8) ^ TABLE[index]
      end

      # Get the initial CRC64 value.
      #
      # CRC64 starts with all bits set to 1, which helps detect
      # leading zeros in the data stream.
      #
      # @return [Integer] 0xFFFFFFFFFFFFFFFF
      def initial_value
        MASK_64
      end

      # Get the final XOR value for CRC64.
      #
      # The final result is XORed with all 1s to invert the bits,
      # which is part of the CRC64 standard.
      #
      # @return [Integer] 0xFFFFFFFFFFFFFFFF
      def final_xor
        MASK_64
      end

      # Get the lookup table for CRC64.
      #
      # @return [Array<Integer>] 256-entry lookup table
      def self.lookup_table
        TABLE
      end
    end
  end
end
