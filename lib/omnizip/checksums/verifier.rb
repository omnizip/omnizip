# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require "zlib"
require "digest"
require_relative "crc64"

module Omnizip
  module Checksums
    # Checksum verification utilities for XZ format
    #
    # XZ supports multiple check types:
    # - 0: None (no checksum)
    # - 1: CRC32 (4 bytes)
    # - 4: CRC64 (8 bytes)
    # - 10: SHA256 (32 bytes)
    class Verifier
      # Check type constants (from XZ spec)
      CHECK_NONE = 0
      CHECK_CRC32 = 1
      CHECK_CRC64 = 4
      CHECK_SHA256 = 10

      # Check sizes in bytes
      CHECK_SIZES = {
        CHECK_NONE => 0,
        CHECK_CRC32 => 4,
        CHECK_CRC64 => 8,
        CHECK_SHA256 => 32,
      }.freeze

      # Verify CRC32 checksum
      #
      # @param data [String] Data to verify
      # @param expected [Integer] Expected CRC32 value
      # @return [Boolean] True if checksum matches
      def self.verify_crc32(data, expected)
        Zlib.crc32(data) == expected
      end

      # Verify CRC64 checksum
      #
      # @param data [String] Data to verify
      # @param expected [Integer] Expected CRC64 value
      # @return [Boolean] True if checksum matches
      def self.verify_crc64(data, expected)
        Crc64.calculate(data) == expected
      end

      # Verify SHA256 checksum
      #
      # @param data [String] Data to verify
      # @param expected [String] Expected SHA256 digest (binary, 32 bytes)
      # @return [Boolean] True if checksum matches
      def self.verify_sha256(data, expected)
        Digest::SHA256.digest(data) == expected
      end

      # Generic verify based on check type
      #
      # @param data [String] Data to verify
      # @param expected [String] Expected checksum (binary format)
      # @param check_type [Integer] Check type (0=None, 1=CRC32, 4=CRC64, 10=SHA256)
      # @return [Boolean] True if checksum matches or check type is None
      # @raise [ArgumentError] If check type is unknown
      def self.verify(data, expected, check_type)
        case check_type
        when CHECK_NONE
          true # No checksum to verify
        when CHECK_CRC32
          expected_crc = expected.unpack1("V")
          verify_crc32(data, expected_crc)
        when CHECK_CRC64
          expected_crc = expected.unpack1("Q<")
          verify_crc64(data, expected_crc)
        when CHECK_SHA256
          verify_sha256(data, expected)
        else
          raise "Unknown check type: #{check_type}"
        end
      end

      # Get check size in bytes
      #
      # @param check_type [Integer] Check type
      # @return [Integer] Size of checksum in bytes
      def self.check_size(check_type)
        CHECK_SIZES.fetch(check_type, 0)
      end

      # Calculate checksum for data based on check type
      #
      # @param data [String] Data to checksum
      # @param check_type [Integer] Check type
      # @return [String] Checksum in binary format
      def self.calculate(data, check_type)
        case check_type
        when CHECK_NONE
          ""
        when CHECK_CRC32
          [Zlib.crc32(data)].pack("V")
        when CHECK_CRC64
          [Crc64.calculate(data)].pack("Q<")
        when CHECK_SHA256
          Digest::SHA256.digest(data)
        else
          raise "Unknown check type: #{check_type}"
        end
      end
    end
  end
end
