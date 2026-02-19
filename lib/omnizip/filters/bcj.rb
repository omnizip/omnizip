# frozen_string_literal: true

#
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

require_relative "../filter"

module Omnizip
  module Filters
    # Unified BCJ (Branch/Call/Jump) filter for multiple architectures
    #
    # This filter preprocesses executable code by converting relative
    # addresses in branch/call instructions to absolute addresses.
    # The transformation is reversible and improves compression ratio.
    #
    # Supports x86, ARM, ARM Thumb, ARM64, PowerPC, IA64, SPARC architectures.
    # Automatically returns correct filter ID for 7z or XZ format.
    #
    # @example Create x86 BCJ filter
    #   bcj = Omnizip::Filters::BCJ.new(architecture: :x86)
    #   bcj.id_for_format(:xz)         # => 0x04
    #   bcj.id_for_format(:seven_zip)  # => 0x03030103
    class BCJ < Filter
      # Architecture-specific configurations
      CONFIG = {
        x86: {
          opcodes: [0xE8, 0xE9],  # CALL, JMP
          address_size: 4,
          instruction_size: 5,
          xz_id: 0x04,
          seven_zip_id: 0x03030103,
        },
        arm: {
          opcodes: [0x0A, 0x0B],  # ARM BL/B conditional
          address_size: 4,
          instruction_size: 4,
          xz_id: 0x07,
          seven_zip_id: 0x03030501,
        },
        armthumb: {
          opcodes: [0xE8, 0xF0, 0xF1], # ARM Thumb BL/B conditional
          address_size: 4,
          instruction_size: 4,
          xz_id: 0x08,
          seven_zip_id: 0x03030701,
        },
        arm64: {
          opcodes: [0x00], # ARM64 BL
          address_size: 4,
          instruction_size: 4,
          xz_id: nil, # Not yet in XZ
          seven_zip_id: 0x03030601,
        },
        powerpc: {
          opcodes: [0x48, 0x18], # PowerPC branch instructions
          address_size: 4,
          instruction_size: 4,
          xz_id: 0x05,
          seven_zip_id: 0x03030205,
        },
        ia64: {
          opcodes: [0x04, 0x05, 0x06, 0x07, 0x08], # IA64 branches
          address_size: 4,
          instruction_size: 4,
          xz_id: 0x06,
          seven_zip_id: 0x03030401,
        },
        sparc: {
          opcodes: [0x04, 0x06, 0x07], # SPARC call/branch
          address_size: 4,
          instruction_size: 4,
          xz_id: 0x09,
          seven_zip_id: 0x03030805,
        },
      }.freeze

      # @return [Symbol] Architecture identifier
      attr_reader :architecture

      # Initialize BCJ filter for specific architecture
      #
      # @param architecture [Symbol] Target architecture (:x86, :arm, :armthumb, :arm64, :powerpc, :ia64, :sparc)
      # @raise [ArgumentError] If architecture is not supported
      def initialize(architecture:)
        unless CONFIG.key?(architecture)
          raise ArgumentError, "Unsupported BCJ architecture: #{architecture}. " \
                               "Supported: #{CONFIG.keys.join(', ')}"
        end

        @architecture = architecture
        @config = CONFIG[architecture]
        super(architecture: architecture, name: "BCJ-#{architecture.to_s.upcase}")
      end

      # Get filter ID for specific format
      #
      # @param format [Symbol] Format identifier (:seven_zip, :xz)
      # @return [Integer] Format-specific filter ID
      # @raise [ArgumentError] If format is not supported
      # @raise [NotImplementedError] If architecture not supported in format
      def id_for_format(format)
        case format
        when :seven_zip
          @config[:seven_zip_id]
        when :xz
          id = @config[:xz_id]
          if id.nil?
            raise NotImplementedError,
                  "#{@architecture} BCJ not yet supported in XZ format"
          end

          id
        else
          raise ArgumentError,
                "Unknown format: #{format}. Supported: :seven_zip, :xz"
        end
      end

      # Encode (preprocess) data for compression
      #
      # Scans for branch/call opcodes and converts relative addresses
      # to absolute addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position (default: 0)
      # @return [String] Encoded binary data
      def encode(data, position = 0)
        return data.dup if data.bytesize < @config[:instruction_size]

        result = data.b
        i = 0
        limit = data.bytesize - @config[:instruction_size]

        while i <= limit
          opcode = result.getbyte(i)

          if @config[:opcodes].include?(opcode)
            # Extract address (little-endian)
            address = extract_address(result, i + 1)

            # Check if valid relative address
            if valid_relative_address?(address)
              # Convert to absolute
              absolute = address + position + i + @config[:instruction_size]
              write_address(result, i + 1, absolute)
            end

            i += @config[:instruction_size]
          else
            i += 1
          end
        end

        result
      end

      # Decode (postprocess) data after decompression
      #
      # Reverses encoding by converting absolute addresses back to
      # relative addresses.
      #
      # @param data [String] Binary executable data
      # @param position [Integer] Current stream position (default: 0)
      # @return [String] Decoded binary data
      def decode(data, position = 0)
        return data.dup if data.bytesize < @config[:instruction_size]

        result = data.b
        i = 0
        limit = data.bytesize - @config[:instruction_size]

        while i <= limit
          opcode = result.getbyte(i)

          if @config[:opcodes].include?(opcode)
            # Extract absolute address
            absolute = extract_address(result, i + 1)

            # Convert to relative
            address = absolute - (position + i + @config[:instruction_size])

            if valid_relative_address?(address)
              write_address(result, i + 1, address)
            end

            i += @config[:instruction_size]
          else
            i += 1
          end
        end

        result
      end

      class << self
        # Get metadata about this filter
        #
        # @return [Hash] Filter metadata
        def metadata
          {
            name: "BCJ",
            description: "Branch/Call/Jump converter for executable files",
            supported_architectures: CONFIG.keys,
            architectures: {
              x86: "x86/x86-64",
              arm: "ARM 32-bit",
              arm64: "ARM 64-bit",
              powerpc: "PowerPC",
              ia64: "IA-64 (Itanium)",
              sparc: "SPARC",
            },
          }
        end
      end

      private

      # Extract address from data at offset (little-endian)
      #
      # @param data [String] Binary data
      # @param offset [Integer] Starting position
      # @return [Integer] Address value
      def extract_address(data, offset)
        bytes = data.byteslice(offset, @config[:address_size]).bytes
        value = bytes.each_with_index.reduce(0) do |acc, (byte, i)|
          acc | (byte << (8 * i))
        end

        # Convert to signed if needed (for 32-bit addresses)
        mask = (1 << (8 * @config[:address_size])) - 1
        value.nobits?(~mask) ? value - (1 << (8 * @config[:address_size])) : value
      end

      # Write address to data at offset (little-endian)
      #
      # @param data [String] Binary data (modified in place)
      # @param offset [Integer] Starting position
      # @param value [Integer] Address value to write
      # @return [void]
      def write_address(data, offset, value)
        @config[:address_size].times do |i|
          data.setbyte(offset + i, value & 0xFF)
          value >>= 8
        end
      end

      # Check if address is a valid relative address
      #
      # Valid relative addresses have high byte of 0x00 or 0xFF,
      # indicating small positive or negative offsets.
      #
      # @param value [Integer] Address value to check
      # @return [Boolean] True if valid relative address
      def valid_relative_address?(value)
        unsigned = value & 0xFFFFFFFF
        high_byte = (unsigned >> 24) & 0xFF
        [0x00, 0xFF].include?(high_byte)
      end
    end
  end
end
