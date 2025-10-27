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
    # CRC32 checksum implementation using IEEE 802.3 polynomial.
    #
    # This implementation uses the standard CRC32 polynomial (0xEDB88320)
    # as used in 7-Zip, ZIP archives, PNG files, and Ethernet frames.
    #
    # The algorithm uses a 256-entry pre-computed lookup table for
    # efficient O(1) per-byte processing, making it suitable for
    # high-performance checksum calculation.
    #
    # Polynomial: 0xEDB88320 (reversed IEEE 802.3)
    # Initial value: 0xFFFFFFFF
    # Final XOR: 0xFFFFFFFF
    # Bit width: 32
    #
    # @example One-shot calculation
    #   checksum = Omnizip::Checksums::Crc32.calculate("abc")
    #   # => 0x352441C2
    #
    # @example Incremental calculation
    #   crc = Omnizip::Checksums::Crc32.new
    #   crc.update("Hello, ")
    #   crc.update("world!")
    #   result = crc.finalize
    class Crc32 < CrcBase
      # IEEE 802.3 polynomial (reversed representation)
      # This is the standard polynomial used in 7-Zip and ZIP files
      POLYNOMIAL = 0xEDB88320

      # 32-bit mask for truncating values
      MASK_32 = 0xFFFFFFFF

      # Pre-computed lookup table for CRC32 calculation
      # Generated using the IEEE 802.3 polynomial
      # This table is computed once at class load time for performance
      TABLE = generate_table(POLYNOMIAL, 32).freeze

      # Process a single byte through the CRC32 algorithm.
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

      # Get the initial CRC32 value.
      #
      # CRC32 starts with all bits set to 1, which helps detect
      # leading zeros in the data stream.
      #
      # @return [Integer] 0xFFFFFFFF
      def initial_value
        MASK_32
      end

      # Get the final XOR value for CRC32.
      #
      # The final result is XORed with all 1s to invert the bits,
      # which is part of the CRC32 standard.
      #
      # @return [Integer] 0xFFFFFFFF
      def final_xor
        MASK_32
      end

      # Get the lookup table for CRC32.
      #
      # @return [Array<Integer>] 256-entry lookup table
      def self.lookup_table
        TABLE
      end
    end
  end
end
