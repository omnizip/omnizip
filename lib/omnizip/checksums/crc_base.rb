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
  module Checksums
    # Abstract base class for CRC (Cyclic Redundancy Check) algorithms.
    #
    # This class provides the common framework for implementing CRC
    # checksums using lookup tables for efficient computation. Subclasses
    # must define their specific polynomial and bit width.
    #
    # The lookup table approach provides O(1) per-byte processing time,
    # making it significantly faster than bit-by-bit calculation.
    #
    # Architecture:
    # - Pre-computed lookup tables stored as class constants
    # - Incremental computation support via update method
    # - Initial and final XOR values for standard CRC variants
    #
    # @abstract Subclass and override polynomial-specific methods
    class CrcBase
      # @return [Integer] current CRC value
      attr_reader :value

      # Initialize a new CRC calculator with default initial value.
      #
      # The initial value is typically all 1s (inverted 0) to detect
      # leading zeros in the input data.
      def initialize
        @value = initial_value
      end

      # Update the CRC value with new data.
      #
      # This method processes the input data byte-by-byte using the
      # lookup table, allowing incremental CRC calculation.
      #
      # @param data [String] binary string to process
      # @return [self] for method chaining
      def update(data)
        data.each_byte do |byte|
          @value = process_byte(@value, byte)
        end
        self
      end

      # Reset the CRC calculator to initial state.
      #
      # @return [self] for method chaining
      def reset
        @value = initial_value
        self
      end

      # Get the finalized CRC value.
      #
      # Applies the final XOR operation required by most CRC standards
      # to produce the final checksum value.
      #
      # @return [Integer] final CRC checksum
      def finalize
        @value ^ final_xor
      end

      # Calculate CRC for data in one operation.
      #
      # This is a convenience method that combines initialize, update,
      # and finalize into a single call.
      #
      # @param data [String] binary string to checksum
      # @return [Integer] final CRC checksum
      def self.calculate(data)
        new.update(data).finalize
      end

      protected

      # Process a single byte through the CRC algorithm.
      #
      # This method must be implemented by subclasses to perform the
      # actual CRC calculation using the lookup table.
      #
      # @param crc [Integer] current CRC value
      # @param byte [Integer] byte to process (0-255)
      # @return [Integer] updated CRC value
      # @abstract
      def process_byte(crc, byte)
        raise NotImplementedError,
              "#{self.class} must implement #process_byte"
      end

      # Get the initial CRC value.
      #
      # @return [Integer] initial value (typically all 1s)
      # @abstract
      def initial_value
        raise NotImplementedError,
              "#{self.class} must implement #initial_value"
      end

      # Get the final XOR value.
      #
      # @return [Integer] value to XOR with final result
      # @abstract
      def final_xor
        raise NotImplementedError,
              "#{self.class} must implement #final_xor"
      end

      # Get the lookup table for this CRC variant.
      #
      # @return [Array<Integer>] 256-entry lookup table
      # @abstract
      def self.lookup_table
        raise NotImplementedError,
              "#{self} must implement .lookup_table"
      end

      # Generate a CRC lookup table for given polynomial.
      #
      # This method pre-computes all possible CRC values for single-byte
      # inputs, enabling efficient O(1) per-byte processing.
      #
      # @param polynomial [Integer] CRC polynomial
      # @param bits [Integer] bit width (32 or 64)
      # @return [Array<Integer>] 256-entry lookup table
      def self.generate_table(polynomial, bits)
        mask = (1 << bits) - 1
        (0..255).map do |i|
          crc = i
          8.times do
            if crc.anybits?(1)
              crc = (crc >> 1) ^ polynomial
            else
              crc >>= 1
            end
          end
          crc & mask
        end
      end
    end
  end
end
