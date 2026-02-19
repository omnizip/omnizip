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

require "stringio"
require_relative "constants"
require_relative "stream_header_parser"
require_relative "stream_footer_parser"
require_relative "block_decoder"
require_relative "index_decoder"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream decoder
      #
      # Decodes a complete XZ stream which consists of:
      # - Stream Header (12 bytes)
      # - Blocks (one or more)
      # - Index
      # - Stream Footer (12 bytes)
      #
      # Reference: /tmp/xz-source/src/liblzma/common/stream_decoder.c
      class StreamDecoder
        # Decode XZ stream from input
        #
        # @param input [IO] Input stream (file, StringIO, etc.)
        # @return [String] Decompressed data
        # @raise [RuntimeError] If stream is invalid
        def self.decode(input)
          header = StreamHeaderParser.parse(input)
          check_type = header[:check_type]

          # Store original input and file size for backward_size validation (if available)
          original_input = input
          original_file_size = input.size if input.respond_to?(:size)

          output, block_count, final_input, block_sizes = decode_blocks(input,
                                                                        check_type)
          index = verify_index(final_input, block_count, block_sizes)

          # Validate backward_size points to valid index position (XZ spec requirement)
          # XZ spec: "The value of Backward Size is the size of the Index field...stored in
          # multiples of four bytes...If the stored value does not match the real size of
          # the Index field, the decoder MUST indicate an error."
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/stream_decoder.c
          if original_input.respond_to?(:seek) && original_file_size&.positive?
            # Use original input and file size for validation
            validate_backward_size_from_footer(original_input,
                                               original_file_size, index[:index_size])
          end

          # Read the stream footer to advance input position past it
          read_stream_footer(final_input, check_type, index[:index_size])

          # Now check for trailing data after the stream footer
          verify_no_trailing_data(final_input)

          output.join.force_encoding(Encoding::BINARY)
        end

        # Decode all blocks from stream until index marker
        #
        # @param input [IO] Input stream
        # @param check_type [Symbol] Checksum type
        # @return [Array, Integer, IO, Array] Output data array, block count, final input stream, and array of block size info
        def self.decode_blocks(input, check_type)
          output = []
          block_count = 0
          block_sizes = [] # Track unpadded and uncompressed sizes for index validation

          loop do
            peek_byte = input.getbyte
            raise FormatError, "Unexpected end of stream" if peek_byte.nil?

            if peek_byte == XzConst::INDEX_INDICATOR
              restore_byte_for_index(input, peek_byte)
              break
            end

            data, decoder = decode_block(input, peek_byte, check_type)
            output << data
            block_count += 1

            # Track block sizes for index validation (per XZ Utils index_hash.c)
            if decoder.unpadded_size && decoder.uncompressed_size
              block_sizes << {
                unpadded_size: decoder.unpadded_size,
                uncompressed_size: decoder.uncompressed_size,
              }
            end

            # If block decoder created a new input (for multi-block files without explicit sizes),
            # use it for the next iteration
            input = decoder.new_input_after_block if decoder.new_input_after_block
          end

          [output, block_count, input, block_sizes]
        end

        # Restore byte to stream for index parser
        #
        # @param input [IO] Input stream
        # @param peek_byte [Integer] Byte to restore
        def self.restore_byte_for_index(input, peek_byte)
          restore_byte(input, peek_byte)
        end

        # Decode single block from stream
        #
        # @param input [IO] Input stream
        # @param peek_byte [Integer] Peeked byte
        # @param check_type [Symbol] Checksum type
        # @return [Array, Hash, BlockDecoder] Decompressed data, block info, and decoder instance
        def self.decode_block(input, peek_byte, check_type)
          restore_byte(input, peek_byte)
          decoder = BlockDecoder.new(input, check_type)
          data = decoder.decode
          [data, decoder]
        end

        # Restore a byte to the input stream
        #
        # @param input [IO] Input stream
        # @param byte [Integer] Byte to restore
        # @raise [RuntimeError] If IO doesn't support ungetbyte
        def self.restore_byte(input, byte)
          return input.ungetbyte(byte) if input.respond_to?(:ungetbyte)

          raise FormatError,
                "IO object doesn't support ungetbyte - cannot parse stream"
        end

        # Parse and verify index matches decoded blocks
        #
        # @param input [IO] Input stream
        # @param block_count [Integer] Number of blocks decoded
        # @param block_sizes [Array<Hash>] Array of {unpadded_size, uncompressed_size} for each block
        # @return [Hash] Index data including index_size for backward_size validation
        # @raise [FormatError] If index doesn't match decoded blocks
        def self.verify_index(input, block_count, block_sizes)
          index = IndexDecoder.parse(input)

          # Validate count matches
          if index[:count] != block_count
            raise FormatError,
                  "Index count mismatch: index says #{index[:count]}, decoded #{block_count}"
          end

          # Validate block sizes match index records (per XZ Utils index_hash.c:244-290)
          # This catches corrupted index files where the sizes don't match the actual blocks
          if block_sizes.any? && index[:records].any?
            # Helper function to calculate VLI ceil4 (round up to multiple of 4)
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/index.h:48
            vli_ceil4 = lambda { |vli|
              (vli + 3) & ~3
            }

            # Calculate sums from actual blocks
            # Note: XZ Utils uses vli_ceil4 on unpadded_size when summing
            blocks_unpadded_sum = block_sizes.sum do |b|
              vli_ceil4.call(b[:unpadded_size])
            end
            blocks_uncompressed_sum = block_sizes.sum do |b|
              b[:uncompressed_size]
            end

            # Calculate sums from index records
            # Note: Index records already contain the unpadded_size, need to ceil4 them too
            index_unpadded_sum = index[:records].sum do |r|
              vli_ceil4.call(r[:unpadded_size])
            end
            index_uncompressed_sum = index[:records].sum do |r|
              r[:uncompressed_size]
            end

            # Validate sums match
            if blocks_unpadded_sum != index_unpadded_sum
              raise FormatError,
                    "Index unpadded size mismatch: blocks sum to #{blocks_unpadded_sum}, " \
                    "index says #{index_unpadded_sum}"
            end

            if blocks_uncompressed_sum != index_uncompressed_sum
              raise FormatError,
                    "Index uncompressed size mismatch: blocks sum to #{blocks_uncompressed_sum}, " \
                    "index says #{index_uncompressed_sum}"
            end

            # Validate individual record sizes match (in correct order)
            # Compare the raw unpadded_size values (not ceiled)
            block_sizes.each_with_index do |block, i|
              record = index[:records][i]
              if block[:unpadded_size] != record[:unpadded_size]
                raise FormatError,
                      "Index record #{i} unpadded size mismatch: block has #{block[:unpadded_size]}, " \
                      "index says #{record[:unpadded_size]}"
              end

              if block[:uncompressed_size] != record[:uncompressed_size]
                raise FormatError,
                      "Index record #{i} uncompressed size mismatch: block has #{block[:uncompressed_size]}, " \
                      "index says #{record[:uncompressed_size]}"
              end
            end
          end

          index
        end

        # Parse and verify footer if input is seekable
        #
        # @param input [IO] Input stream
        # @param check_type [Symbol] Expected checksum type
        # @param index_size [Integer, nil] Actual index size for backward_size validation
        def self.verify_footer_if_seekable(input, check_type, index_size = nil)
          return unless input.respond_to?(:seek) && input.respond_to?(:size) && input.size

          original_pos = input.pos
          input.seek(-12, ::IO::SEEK_END)
          footer = StreamFooterParser.parse(input)
          input.pos = original_pos

          # Verify check type matches
          return if footer[:check_type] != check_type

          # Validate backward_size against actual index size (XZ spec requirement)
          # XZ spec: "If the stored value does not match the real size of the Index field,
          # the decoder MUST indicate an error."
          if index_size
            # Convert stored_backward_size to real size: (stored + 1) * 4
            real_backward_size = (footer[:backward_size] + 1) * 4
            if real_backward_size != index_size
              raise FormatError, "Backward size mismatch: footer indicates #{real_backward_size} bytes, " \
                                 "but index is #{index_size} bytes"
            end
          end
        end

        # Read and verify the stream footer from the current position
        #
        # @param input [IO] Input stream positioned at the start of the stream footer
        # @param check_type [Symbol] Expected checksum type
        # @param index_size [Integer, nil] Actual index size for backward_size validation
        # @raise [FormatError] If footer is invalid or doesn't match expected values
        def self.read_stream_footer(input, check_type, index_size = nil)
          footer = StreamFooterParser.parse(input)

          # Verify check type matches
          if footer[:check_type] != check_type
            raise FormatError,
                  "Stream footer check type mismatch: expected #{check_type}, got #{footer[:check_type]}"
          end

          # Validate backward_size against actual index size (XZ spec requirement)
          if index_size
            # Convert stored_backward_size to real size: (stored + 1) * 4
            real_backward_size = (footer[:backward_size] + 1) * 4
            if real_backward_size != index_size
              raise FormatError, "Backward size mismatch: footer indicates #{real_backward_size} bytes, " \
                                 "but index is #{index_size} bytes"
            end
          end

          footer
        end

        # Verify there's no invalid trailing data after the stream footer
        #
        # According to XZ spec, after a stream there can be:
        # 1. Stream padding (null bytes to 4-byte boundary)
        # 2. Another stream (concatenated streams)
        #
        # For bad-0cat-header_magic.xz style files with invalid extra data, we must reject them.
        # XZ Utils rejects these with LZMA_FORMAT_ERROR when the extra data is not valid.
        #
        # @param input [IO] Input stream
        # @raise [FormatError] If there's invalid trailing data
        def self.verify_no_trailing_data(input)
          return unless input.respond_to?(:pos) && input.respond_to?(:getbyte)

          # Skip stream padding (null bytes)
          # Stream padding must be a multiple of 4 bytes (per XZ spec)
          padding_bytes = 0
          loop do
            byte = input.getbyte
            break if byte.nil?

            if byte.zero?
              padding_bytes += 1
            else
              # Non-zero byte found - this should be a new stream or it's invalid
              # Restore the byte and check if it's a valid stream header
              input.ungetbyte(byte) if input.respond_to?(:ungetbyte)

              # Stream padding must be a multiple of 4 bytes
              if padding_bytes % 4 != 0
                raise FormatError,
                      "Invalid stream padding: not a multiple of 4 bytes"
              end

              # Check if this looks like a valid XZ stream header
              verify_or_reject_trailing_stream(input)
              break
            end
          end

          # If we reached EOF (no more data after padding), verify padding is multiple of 4
          # XZ spec: "Stream Padding MUST contain only null bytes...the size of Stream
          # Padding MUST be a multiple of four bytes."
          if padding_bytes.positive? && padding_bytes % 4 != 0
            raise FormatError,
                  "Invalid stream padding at EOF: #{padding_bytes} bytes (not a multiple of 4)"
          end
        end

        # Verify that trailing data (if any) is a valid XZ stream
        #
        # @param input [IO] Input stream positioned at potential next stream
        # @raise [FormatError] If the trailing data is not a valid XZ stream
        def self.verify_or_reject_trailing_stream(input)
          # Try to peek at the stream header magic
          header_magic = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] # XZ magic bytes

          # Read the next 6 bytes to check for stream header
          potential_header = []
          6.times do
            byte = input.getbyte
            break if byte.nil?

            potential_header << byte
          end

          # Restore the bytes we read
          if input.respond_to?(:ungetbyte)
            potential_header.reverse_each do |b|
              input.ungetbyte(b)
            end
          end

          # If we couldn't read 6 bytes, it's EOF - that's fine
          return if potential_header.size < 6

          # Check if it matches XZ stream header magic
          potential_header.each_with_index do |byte, i|
            if byte != header_magic[i]
              # Invalid trailing data - not a valid XZ stream
              raise FormatError,
                    "Trailing data: invalid stream header (byte #{i}: 0x#{byte.to_s(16)} != 0x#{header_magic[i].to_s(16)})"
            end
          end

          # At this point, we have a valid concatenated stream header
          # We don't decode additional streams yet, but we don't reject them either
          # The XZ spec allows concatenated streams, so having valid stream data after
          # the first stream is OK - we just stop after decoding the first stream
        end

        # Validate that backward_size in footer points to valid index position
        #
        # This is required by the XZ spec: the backward_size must match the actual
        # index size, and the index must start with the index indicator (0x00).
        # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/stream_decoder.c
        #
        # @param input [IO] Input stream (must be seekable)
        # @param file_size [Integer] Total file size in bytes
        # @param index_size [Integer] Actual index size in bytes
        # @raise [FormatError] If backward_size points to invalid position
        def self.validate_backward_size_from_footer(input, file_size,
_index_size)
          return unless input.respond_to?(:seek)
          return if file_size.nil? || file_size.zero?

          # Save current position
          original_pos = input.pos

          # Seek to stream footer (last 12 bytes)
          input.seek(-12, ::IO::SEEK_END)

          # Verify we're at the footer by checking magic bytes
          footer_start = input.pos
          input.seek(10, ::IO::SEEK_CUR)
          magic_bytes = input.read(2)
          if magic_bytes.nil? || magic_bytes.bytesize < 2 || magic_bytes != [
            0x59, 0x5A
          ]
            input.seek(original_pos, ::IO::SEEK_SET)
            return # Not a valid footer, skip validation
          end

          # Seek back to footer start and then to backward_size field
          input.seek(footer_start, ::IO::SEEK_SET)
          input.seek(4, ::IO::SEEK_CUR)
          backward_size_bytes = input.read(4)
          if backward_size_bytes.nil? || backward_size_bytes.bytesize < 4
            input.seek(original_pos, ::IO::SEEK_SET)
            return
          end

          backward_size = backward_size_bytes.unpack1("V")

          # Calculate real backward size: (stored + 1) * 4
          real_backward_size = (backward_size + 1) * 4

          # Calculate where index should start
          # Stream structure: [blocks] [index + indicator] [padding] [footer 12 bytes]
          # Index (including indicator) starts at: file_size - footer_size - real_backward_size
          expected_index_start = file_size - 12 - real_backward_size

          # Validate index start position is valid
          if expected_index_start.negative?
            input.seek(original_pos, ::IO::SEEK_SET)
            raise FormatError,
                  "Invalid backward size: #{backward_size} (#{real_backward_size} bytes) " \
                  "would place index at negative position #{expected_index_start}"
          end

          if expected_index_start >= file_size
            input.seek(original_pos, ::IO::SEEK_SET)
            raise FormatError,
                  "Invalid backward size: #{backward_size} (#{real_backward_size} bytes) " \
                  "would place index past end of file (position #{expected_index_start}, file size #{file_size})"
          end

          # Check that the byte at the expected index start is the index indicator (0x00)
          input.seek(expected_index_start, ::IO::SEEK_SET)
          index_indicator = input.getbyte

          if index_indicator.nil?
            input.seek(original_pos, ::IO::SEEK_SET)
            raise FormatError,
                  "Invalid backward size: expected index indicator (0x00) at position #{expected_index_start}, " \
                  "but reached end of file"
          end

          if index_indicator != XzConst::INDEX_INDICATOR
            input.seek(original_pos, ::IO::SEEK_SET)
            raise FormatError,
                  "Invalid backward size: expected index indicator (0x00) at position #{expected_index_start}, " \
                  "but found 0x#{index_indicator.to_s(16).upcase}"
          end

          # Restore original position
          input.seek(original_pos, ::IO::SEEK_SET)
        end
      end
    end
  end
end
