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

require_relative "xz_utils_decoder"
require_relative "../../checksums/crc32"
require "stringio"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      #
      # Decoder for .lz (lzip) format
      #
      # This is the lzip format, a DIFFERENT container format from both
      # XZ and .lzma (LZMA_Alone). Lzip was created as an alternative to
      # the legacy .lzma format with better integrity checking.
      #
      # File format:
      # - Magic bytes: "LZIP" (0x4C 0x5A 0x49 0x50)
      # - Version (1 byte): 0 or 1
      # - Dictionary size (1 byte): encoded format
      # - LZMA1 compressed stream (with fixed LC=3, LP=0, PB=2)
      # - Footer:
      #   - Version 0 (12 bytes): CRC32 (4) + Uncompressed size (8)
      #   - Version 1 (20 bytes): CRC32 (4) + Uncompressed size (8) + Member size (8)
      #
      # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/lzip_decoder.c
      #
      # This decoder uses the same LZMA1 decoding engine as XZ format,
      # but with the lzip container format and CRC32 integrity checking.
      #
      # @example Decode .lz file
      #   data = File.binread("file.lz")
      #   decoder = Omnizip::Algorithms::LZMA::LzipDecoder.new(StringIO.new(data))
      #   result = decoder.decode_stream
      #
      class LzipDecoder
        # Lzip magic bytes: "LZIP" in ASCII
        # Reference: lzip_decoder.c:106
        MAGIC = [0x4C, 0x5A, 0x49, 0x50].freeze

        # Fixed LC/LP/PB values for lzip format
        # Reference: lzip_decoder.c:23-26
        LZIP_LC = 3
        LZIP_LP = 0
        LZIP_PB = 2

        # Footer sizes
        # Reference: lzip_decoder.c:19-21
        LZIP_V0_FOOTER_SIZE = 12
        LZIP_V1_FOOTER_SIZE = 20
        LZIP_FOOTER_SIZE_MAX = LZIP_V1_FOOTER_SIZE

        # Minimum and maximum dictionary sizes (in bytes)
        # Reference: lzip_decoder.c:197-198
        MIN_DICT_SIZE = 4096 # 4 KiB
        MAX_DICT_SIZE = (512 << 20) # 512 MiB

        # Initialize the decoder with .lz format input
        #
        # @param input [IO] Input stream of .lz compressed data
        # @param options [Hash] Decoding options
        # @option options [Boolean] :ignore_check If true, skip CRC32 verification (default: false)
        # @option options [Boolean] :concatenated If true, decode concatenated .lz members (default: false)
        # @raise [Omnizip::DecompressionError] If header is invalid or unsupported
        def initialize(input, options = {})
          @input = input
          @ignore_check = options.fetch(:ignore_check, false)
          # Concatenated mode is enabled by default (lzip natively supports multiple members)
          @concatenated = options.fetch(:concatenated, true)

          # Parse .lz header
          parse_header

          # Track member size (including header and footer)
          # We start with the 6 bytes we've already read (magic + version + dict_size)
          @member_size = 6

          # For concatenated mode, track if this is the first member
          @first_member = true

          # Initialize CRC32 calculator
          @crc32 = 0
          @uncompressed_size = 0
        end

        # Decode the .lz stream
        #
        # @param output [IO, nil] Optional output stream
        # @return [String, Integer] Decompressed data or bytes written
        def decode_stream(output = nil)
          # For concatenated mode, accumulate all decoded data
          all_decoded_data = String.new(encoding: Encoding::BINARY)
          bytes_written = 0
          result = nil # Initialize result variable

          loop do
            # Track the starting position of compressed data
            start_pos = @input.pos

            # Initialize the XZ Utils LZMA decoder with fixed lzip parameters
            decoder = XzUtilsDecoder.new(@input,
                                         lzma2_mode: true,
                                         lc: LZIP_LC,
                                         lp: LZIP_LP,
                                         pb: LZIP_PB,
                                         dict_size: @dict_size,
                                         uncompressed_size: 0xFFFFFFFFFFFFFFFF) # Unknown size, allow EOPM

            # Decode the LZMA stream (allow EOPM for .lz format)
            # Get decoded data as string (no output stream)
            decoded_data = decoder.decode_stream(nil, check_rc_finished: false)

            # If caller provided output stream, write to it
            if output
              output.write(decoded_data)
              bytes_written += decoded_data.bytesize
              result = bytes_written
            else
              all_decoded_data << decoded_data
              result = all_decoded_data
            end

            # Calculate member size (header + compressed data + footer)
            # We calculate it here (compressed data + header), then add footer size below
            @member_size = @input.pos - start_pos + 6 # +6 for header bytes

            # Calculate and verify CRC32
            if @ignore_check
              # Skip footer
              footer_size = @version.zero? ? LZIP_V0_FOOTER_SIZE : LZIP_V1_FOOTER_SIZE
              @input.read(footer_size)
              @member_size += footer_size
            else
              data_to_crc = decoded_data || +""
              calculated_crc = Omnizip::Checksums::Crc32.calculate(data_to_crc)
              @uncompressed_size = data_to_crc.bytesize

              # Read and verify footer (also updates @member_size to include footer)
              verify_footer(calculated_crc)
            end

            # Check for concatenated members
            break unless @concatenated

            # Peek ahead to check if there's another LZIP member
            break unless has_next_member?

            # Parse header for next member
            parse_header
          end

          # Return decoded data or bytes written
          result
        end

        private

        # Check if there's another concatenated LZIP member
        # Peeks ahead without consuming the magic bytes
        #
        # @return [Boolean] true if another member is present
        def has_next_member?
          # Peek at next 4 bytes to check for magic
          magic_bytes = @input.read(4)
          return false if magic_bytes.nil? || magic_bytes.bytesize < 4

          # Check if it's LZIP magic
          is_lzip = magic_bytes.getbyte(0) == MAGIC[0] &&
            magic_bytes.getbyte(1) == MAGIC[1] &&
            magic_bytes.getbyte(2) == MAGIC[2] &&
            magic_bytes.getbyte(3) == MAGIC[3]

          # Put the bytes back by seeking back
          @input.seek(-4, ::IO::SEEK_CUR) if is_lzip

          is_lzip
        end

        # Parse .lz format header
        #
        # Format (from lzip_decoder.c):
        # - Magic bytes: "LZIP" (4 bytes)
        # - Version (1 byte): 0 or 1
        # - Dictionary size (1 byte): encoded format
        #
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/lzip_decoder.c
        #
        # @return [void]
        # @raise [Omnizip::DecompressionError] If header is invalid
        def parse_header
          # Step 1: Verify magic bytes (SEQ_ID_STRING)
          # Reference: lzip_decoder.c:104-153
          magic_bytes = @input.read(4)
          if magic_bytes.nil? || magic_bytes.bytesize < 4
            raise Omnizip::DecompressionError,
                  "Incomplete .lz header: missing magic bytes"
          end

          4.times do |i|
            if magic_bytes.getbyte(i) != MAGIC[i]
              raise Omnizip::DecompressionError, "Invalid .lz header: magic bytes don't match LZIP (expected #{MAGIC.map do |b|
                "0x#{b.to_s(16).upcase}"
              end.join(' ')}, got #{magic_bytes.bytes.map do |b|
                                    "0x#{b.to_s(16).upcase}"
                                  end.join(' ')})"
            end
          end

          # Step 2: Read version byte (SEQ_VERSION)
          # Reference: lzip_decoder.c:156-174
          version_byte = @input.getbyte
          if version_byte.nil?
            raise Omnizip::DecompressionError,
                  "Incomplete .lz header: missing version byte"
          end

          @version = version_byte

          # We support version 0 and unextended version 1
          # Reference: lzip_decoder.c:163-164
          if @version > 1
            raise Omnizip::UnsupportedFormatError,
                  "Unsupported .lz version: #{@version} (only 0 and 1 are supported)"
          end

          # Step 3: Parse dictionary size (SEQ_DICT_SIZE)
          # Reference: lzip_decoder.c:177-222
          dict_size_byte = @input.getbyte
          if dict_size_byte.nil?
            raise Omnizip::DecompressionError,
                  "Incomplete .lz header: missing dictionary size byte"
          end

          # Decode dictionary size from the encoded byte
          # The five lowest bits are for the base-2 logarithm of the dictionary size
          # and the highest three bits are the fractional part (0/16 to 7/16)
          # Reference: lzip_decoder.c:183-204
          b2log = dict_size_byte & 0x1F
          fracnum = dict_size_byte >> 5

          # Validate range: [4 KiB, 512 MiB]
          # Reference: lzip_decoder.c:198-199
          if b2log < 12 || b2log > 29 || (b2log == 12 && fracnum.positive?)
            raise Omnizip::DecompressionError,
                  "Invalid .lz header: dictionary size byte 0x#{dict_size_byte.to_s(16).upcase} is out of valid range"
          end

          # Calculate: 2^[b2log] - [fracnum] * 2^([b2log] - 4)
          # Reference: lzip_decoder.c:201-204
          @dict_size = (1 << b2log) - (fracnum << (b2log - 4))

          # Sanity checks
          if @dict_size < MIN_DICT_SIZE
            raise Omnizip::DecompressionError,
                  "Dictionary size calculation error: too small"
          end
          if @dict_size > MAX_DICT_SIZE
            raise Omnizip::DecompressionError,
                  "Dictionary size calculation error: too large"
          end
        end

        # Verify .lz format footer
        #
        # Format (from lzip_decoder.c):
        # - CRC32 of uncompressed data (4 bytes, little-endian)
        # - Uncompressed size (8 bytes, little-endian)
        # - Member size (8 bytes, little-endian) - only for version 1
        #
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/lzip_decoder.c:277-309
        #
        # @param calculated_crc [Integer] Calculated CRC32 of uncompressed data
        # @raise [Omnizip::DecompressionError] If footer is invalid or checksum mismatch
        def verify_footer(calculated_crc)
          footer_size = @version.zero? ? LZIP_V0_FOOTER_SIZE : LZIP_V1_FOOTER_SIZE
          footer = @input.read(footer_size)
          if footer.nil? || footer.bytesize < footer_size
            raise Omnizip::DecompressionError,
                  "Incomplete .lz footer: expected #{footer_size} bytes, got #{footer&.bytesize || 0}"
          end

          # Update member_size to include the footer
          @member_size += footer_size

          # Parse CRC32 (little-endian)
          stored_crc = footer.getbyte(0) | (footer.getbyte(1) << 8) |
            (footer.getbyte(2) << 16) | (footer.getbyte(3) << 24)

          # Verify CRC32
          if calculated_crc != stored_crc
            raise Omnizip::ChecksumError,
                  "CRC32 mismatch: calculated 0x#{calculated_crc.to_s(16).upcase}, stored 0x#{stored_crc.to_s(16).upcase}"
          end

          # Parse and verify uncompressed size (little-endian)
          stored_uncompressed_size = footer.getbyte(4) | (footer.getbyte(5) << 8) |
            (footer.getbyte(6) << 16) | (footer.getbyte(7) << 24) |
            (footer.getbyte(8) << 32) | (footer.getbyte(9) << 40) |
            (footer.getbyte(10) << 48) | (footer.getbyte(11) << 56)

          if @uncompressed_size != stored_uncompressed_size
            raise Omnizip::ChecksumError,
                  "Uncompressed size mismatch: decoded #{@uncompressed_size}, stored #{stored_uncompressed_size}"
          end

          # For version 1, verify member size
          if @version.positive?
            stored_member_size = footer.getbyte(12) | (footer.getbyte(13) << 8) |
              (footer.getbyte(14) << 16) | (footer.getbyte(15) << 24) |
              (footer.getbyte(16) << 32) | (footer.getbyte(17) << 40) |
              (footer.getbyte(18) << 48) | (footer.getbyte(19) << 56)

            if @member_size != stored_member_size
              raise Omnizip::ChecksumError,
                    "Member size mismatch: decoded #{@member_size}, stored #{stored_member_size}"
            end
          end
        end

        # Wrapper input stream that tracks bytes read
        class TrackingInputStream
          attr_reader :bytes_read

          def initialize(input, start_offset = 0)
            @input = input
            @bytes_read = start_offset
          end

          def read(size = nil)
            data = @input.read(size)
            @bytes_read += data.bytesize if data
            data
          end

          def getbyte
            byte = @input.getbyte
            @bytes_read += 1 if byte
            byte
          end

          def eof?
            @input.eof?
          end
        end
      end
    end
  end
end
