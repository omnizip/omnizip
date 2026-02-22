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
require_relative "block_header_parser"

module Omnizip
  module Formats
    module XzFormat
      # XZ Block decoder
      #
      # Decodes a single XZ block which consists of:
      # - Block Header
      # - Compressed Data
      # - Block Padding (to 4-byte boundary)
      # - Check (CRC32/CRC64/SHA256)
      #
      # Reference: /tmp/xz-source/src/liblzma/common/block_decoder.c
      class BlockDecoder
        # Filter IDs
        FILTER_LZMA2 = 0x21

        # XZ spec: max valid prop is 40 (gives ~2GB dict)
        # Cap at 40 to prevent memory exhaustion from malformed files
        MAX_DICT_PROP = 40
        MAX_DICT_SIZE = 64 * 1024 * 1024 # 64MB practical limit

        # Accessor for new input after block (used by stream decoder for multi-block files)
        attr_reader :new_input_after_block
        # Accessor for block size information (used for index validation)
        attr_reader :unpadded_size, :uncompressed_size

        # Wrapper for counting bytes read from a stream
        class CountingInputStream
          attr_reader :bytes_read

          def initialize(stream)
            @stream = stream
            @bytes_read = 0
          end

          def read(length = nil, outbuf = nil)
            result = @stream.read(length, outbuf)
            if result
              bytes_read = result.bytesize
              @bytes_read += bytes_read
            end
            result
          end

          def getbyte
            byte = @stream.getbyte
            @bytes_read += 1 if byte
            byte
          end

          def eos?
            @stream.eos?
          end

          def set_encoding(enc)
            @stream.set_encoding(enc) if @stream.respond_to?(:set_encoding)
          end
        end

        # Initialize block decoder
        #
        # @param input [IO] Input stream positioned at block header
        # @param check_type [Integer] Check type (0=None, 1=CRC32, 4=CRC64, 10=SHA256)
        def initialize(input, check_type)
          @input = input
          @check_type = check_type
          @new_input_after_block = nil # Track new input for stream decoder
          @data_already_decompressed = false # Track if LZMA2 already decoded the data
          @unpadded_size = nil # Track unpadded block size (for index validation)
          @uncompressed_size = nil # Track uncompressed size (for index validation)
        end

        # Decode block
        #
        # @return [Array<String, Hash>] Decompressed data and block info:
        #   - data: String (decompressed data)
        #   - info: Hash with header info
        # @raise [RuntimeError] If block is invalid or checksum mismatch
        def decode
          # Parse block header
          header = BlockHeaderParser.parse(@input)

          # Read compressed data
          compressed_size = header[:compressed_size]
          check_size = Checksums::Verifier.check_size(@check_type)

          if ENV["XZ_BLOCK_DEBUG"]
            warn "DEBUG: decode - compressed_size=#{compressed_size.inspect}, check_type=#{@check_type}"
            warn "DEBUG: @input.class=#{@input.class}, @input.respond_to?(:pos)=#{@input.respond_to?(:pos)}"
            pos = @input.respond_to?(:pos) ? @input.pos : "N/A"
            warn "DEBUG: @input.pos=#{pos}"
          end

          if compressed_size.nil?
            # Compressed size is not present in header - need to determine block boundary
            # Read all remaining data
            all_remaining = @input.read

            # Decode LZMA2 and track how many bytes it consumes
            uncompressed_data, consumed_bytes = decode_lzma2_with_consumption_tracking(
              all_remaining: all_remaining,
              filters: header[:filters],
            )

            # Mark that data is already decompressed (LZMA2 only for now)
            @data_already_decompressed = true

            # Calculate padding and check positions
            # Block structure: [compressed data] [padding to 4-byte boundary] [check]
            padding_needed = (4 - (consumed_bytes % 4)) % 4
            check_start_pos = consumed_bytes + padding_needed

            # XZ Utils: Validate padding bytes are all zeros
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/block_decoder.c:131-139
            if padding_needed.positive?
              padding_bytes = all_remaining.byteslice(consumed_bytes,
                                                      padding_needed)
              if padding_bytes.nil? || padding_bytes.bytesize < padding_needed
                raise Omnizip::FormatError,
                      "Unexpected end of stream in block padding"
              end
              # Verify padding is all zeros
              unless padding_bytes.bytes.all?(0)
                raise Omnizip::FormatError,
                      "Block padding contains non-zero bytes"
              end
            end

            if ENV["XZ_BLOCK_DEBUG"]
              warn "DEBUG: consumed_bytes=#{consumed_bytes}, padding_needed=#{padding_needed}, check_start_pos=#{check_start_pos}"
              warn "DEBUG: all_remaining.bytesize=#{all_remaining.bytesize}"
            end

            if check_start_pos + check_size > all_remaining.bytesize
              raise Omnizip::FormatError,
                    "Invalid check position"
            end

            check_bytes = all_remaining.byteslice(check_start_pos, check_size)

            # Create new input with remaining data (after this block)
            total_block_size = check_start_pos + check_size
            data_after_block = all_remaining[total_block_size..]

            # Create new StringIO with remaining data
            new_input = StringIO.new(data_after_block)
            new_input.set_encoding(Encoding::BINARY)

            # Store the new input for the stream decoder to use
            @new_input_after_block = new_input
          else
            compressed_data = @input.read(compressed_size)
            if compressed_data.nil? || compressed_data.bytesize < compressed_size
              raise Omnizip::IOError,
                    "Unexpected end of stream in compressed data: expected #{compressed_size} bytes"
            end

            # Read block padding (align to 4-byte boundary)
            # Block header is always 4-byte aligned, so we only need to pad the data
            padding_needed = (4 - (compressed_size % 4)) % 4
            if padding_needed.positive?
              padding = @input.read(padding_needed)
              if padding.nil? || padding.bytesize < padding_needed
                raise Omnizip::IOError,
                      "Unexpected end of stream in block padding"
              end
              # Verify padding is all zeros
              unless padding.bytes.all?(0)
                raise Omnizip::FormatError,
                      "Block padding contains non-zero bytes"
              end
            end

            # Read check
            if check_size.positive?
              check_bytes = @input.read(check_size)
              if check_bytes.nil? || check_bytes.bytesize < check_size
                raise Omnizip::IOError,
                      "Unexpected end of stream in block check"
              end
            else
              check_bytes = ""
            end

            # When compressed_size is explicit, the input stream is now correctly
            # positioned at the start of the next block, so no need to create new input
          end

          # Decode filter chain (for now, just LZMA2)
          # Skip if data was already decompressed by decode_lzma2_with_consumption_tracking
          if @data_already_decompressed
            # LZMA2 was already decoded, but we may still have other filters to apply
            # For multi-filter chains, apply remaining filters in reverse order
            filters_to_process = header[:filters].dup
            # Remove the LZMA2 filter that was already processed
            filters_to_process.reject! { |f| f[:id] == FILTER_LZMA2 }

            if filters_to_process.empty?
              # No remaining filters
              uncompressed_data = @decompressed_data
            else
              # Apply remaining filters in reverse order
              data = @decompressed_data
              filters_to_process.reverse_each do |filter|
                data = decode_single_filter(data, filter)
              end
              uncompressed_data = data
            end
          else
            uncompressed_data = decode_filters(compressed_data,
                                               header[:filters])
          end

          # Verify uncompressed size matches header (if present)
          if header[:uncompressed_size] && (uncompressed_data.bytesize != header[:uncompressed_size])
            raise Omnizip::DecompressionError,
                  "Uncompressed size mismatch: header says #{header[:uncompressed_size]}, got #{uncompressed_data.bytesize}"
          end

          # DEBUG: Show output before checksum check
          if ENV["DEBUG_CHECKSUM"]
            puts "DEBUG: uncompressed_data.bytesize=#{uncompressed_data.bytesize}"
            puts "DEBUG: first 100 bytes: #{uncompressed_data[0, 100].inspect}"
            puts "DEBUG: last 50 bytes: #{uncompressed_data[-50..].inspect}"
          end

          # Verify check
          unless Checksums::Verifier.verify(uncompressed_data, check_bytes,
                                            @check_type)
            raise Omnizip::ChecksumError,
                  "Block checksum mismatch for check type #{@check_type}"
          end

          # Track block sizes for index validation (per XZ Utils index_hash.c)
          # Unpadded size = block header + compressed data + check (NO padding)
          # This is used to validate against the index records
          # Reference: xz-file-format-1.2.1.txt Section 3.3.2:
          #   "Unpadded Size is the size of the Block Header, Compressed Data,
          #    and Check fields. The Block Padding field is NOT included."
          @uncompressed_size = uncompressed_data.bytesize

          # Calculate unpadded block size (excludes padding per XZ spec)
          # Block structure: [block header] [compressed data] [padding] [check]
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/block_decoder.c
          header_size = header[:header_size] || 0
          if compressed_size.nil?
            # When compressed_size wasn't specified, we tracked consumed_bytes
            # unpadded_size = header_size + consumed_bytes + check_size (NO padding)
            # Note: BlockHeaderParser already consumed the header from input
            # For the size calculation, we need to include header size
            actual_compressed_size = consumed_bytes
            @unpadded_size = header_size + actual_compressed_size + check_size
          else
            # When compressed_size was specified
            @unpadded_size = header_size + compressed_size + check_size
          end

          uncompressed_data
        end

        private

        # Decode filter chain
        #
        # @param compressed_data [String] Compressed data
        # @param filters [Array<Hash>] Filter definitions
        # @return [String] Decompressed data
        # @raise [RuntimeError] If filter chain is unsupported
        def decode_filters(compressed_data, filters)
          case filters.size
          when 0
            # No filters - passthrough
            compressed_data
          when 1
            # Single filter - should be LZMA2
            decode_single_filter(compressed_data, filters[0])
          else
            # Multiple filters - decode in reverse order
            # For now, only support LZMA2
            data = compressed_data
            filters.reverse_each do |filter|
              data = decode_single_filter(data, filter)
            end
            data
          end
        end

        # Decode a single filter
        #
        # @param compressed_data [String] Compressed data
        # @param filter [Hash] Filter definition with :id and :properties
        # @return [String] Decompressed data
        def decode_single_filter(compressed_data, filter)
          case filter[:id]
          when FILTER_LZMA2
            decode_lzma2(compressed_data, filter[:properties])
          when 0x03 # FILTER_DELTA
            decode_delta(compressed_data, filter[:properties])
          when 0x04 # x86 BCJ
            decode_bcj(compressed_data, :x86, filter[:properties])
          when 0x05 # PowerPC BCJ
            decode_bcj(compressed_data, :powerpc, filter[:properties])
          when 0x06 # IA-64 BCJ
            decode_bcj(compressed_data, :ia64, filter[:properties])
          when 0x07 # ARM BCJ
            decode_bcj(compressed_data, :arm, filter[:properties])
          when 0x08 # ARM Thumb BCJ
            decode_bcj(compressed_data, :armthumb, filter[:properties])
          when 0x09 # SPARC BCJ
            decode_bcj(compressed_data, :sparc, filter[:properties])
          when 0x0A # ARM64 BCJ
            decode_bcj_arm64(compressed_data, filter[:properties])
          else
            raise Omnizip::FormatError,
                  "Unsupported filter ID: 0x#{filter[:id].to_s(16).upcase}"
          end
        end

        # Decode Delta filter
        #
        # @param data [String] Input data
        # @param properties [String, nil] Filter properties (first byte is distance - 1)
        # @return [String] Delta-transformed data
        def decode_delta(data, properties)
          # XZ Utils: lzma_delta_props_decode sets opt->dist = props[0] + 1
          # So if props[0] = 0, distance = 1; if props[0] = 255, distance = 256
          distance = if properties&.bytesize&.positive?
                       (properties.getbyte(0) || 0) + 1
                     else
                       1
                     end

          Omnizip::Filters::Delta.new(distance).decode(data, 0)
        end

        # Decode BCJ filter
        #
        # @param data [String] Input data
        # @param architecture [Symbol] Target architecture
        # @param properties [String, nil] Filter properties
        # @return [String] BCJ-transformed data
        def decode_bcj(data, architecture, properties)
          # Get start_offset from properties if present
          # XZ filter properties for BCJ: first 4 bytes are start_offset (big-endian)
          start_offset = 0
          if properties&.bytesize&.>= 4
            start_offset = (properties.getbyte(0) || 0) << 24
            start_offset |= (properties.getbyte(1) || 0) << 16
            start_offset |= (properties.getbyte(2) || 0) << 8
            start_offset |= properties.getbyte(3) || 0
          end

          # Use the appropriate BCJ filter based on architecture
          case architecture
          when :x86
            Omnizip::Filters::BCJ.new(architecture: :x86).decode(data,
                                                                 start_offset)
          when :powerpc
            Omnizip::Filters::BCJ.new(architecture: :powerpc).decode(data,
                                                                     start_offset)
          when :ia64
            Omnizip::Filters::BCJ.new(architecture: :ia64).decode(data,
                                                                  start_offset)
          when :arm
            Omnizip::Filters::BCJ.new(architecture: :arm).decode(data,
                                                                 start_offset)
          when :armthumb
            Omnizip::Filters::BCJ.new(architecture: :armthumb).decode(data,
                                                                      start_offset)
          when :sparc
            Omnizip::Filters::BCJ.new(architecture: :sparc).decode(data,
                                                                   start_offset)
          when :arm64
            Omnizip::Filters::BCJ.new(architecture: :arm64).decode(data,
                                                                   start_offset)
          else
            raise Omnizip::FormatError,
                  "Unsupported BCJ architecture: #{architecture}"
          end
        end

        # Decode ARM64 BCJ filter
        #
        # XZ Utils pattern (simple/arm64.c):
        # - Converts BL instructions (bits 26-31 == 0x25) with +/-128 MiB range
        # - Converts ADRP instructions (bits 25-29 == 0x10000) with +/-512 MiB range
        # - Uses start_offset for position calculation
        #
        # @param data [String] Input data
        # @param properties [String, nil] Filter properties (first 4 bytes are start_offset)
        # @return [String] ARM64 BCJ-transformed data
        def decode_bcj_arm64(data, properties)
          # Get start_offset from properties if present
          # XZ filter properties for BCJ: first 4 bytes are start_offset (little-endian per XZ spec)
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/simple/simple_decoder.c:30
          start_offset = 0
          if properties&.bytesize&.>= 4
            # Read as little-endian (LSB first)
            start_offset = properties.getbyte(0) || 0
            start_offset |= (properties.getbyte(1) || 0) << 8
            start_offset |= (properties.getbyte(2) || 0) << 16
            start_offset |= (properties.getbyte(3) || 0) << 24
          end

          # DEBUG: Show input data
          if ENV["DEBUG_ARM64_BCJ"]
            puts "DEBUG ARM64 BCJ: start_offset=0x#{start_offset.to_s(16).upcase}"
            puts "DEBUG ARM64 BCJ: input (first 32 bytes):"
            puts data[0, 32].unpack1("H*").scan(/../).each_slice(16).map { |row|
              row.join(" ")
            }.join("\n")
          end

          # XZ Utils ARM64 BCJ filter implementation
          result = data.b
          size = data.bytesize & ~3 # Round down to multiple of 4

          (0...size).step(4) do |i|
            pc = (start_offset + i) & 0xFFFFFFFF
            instr = read_uint32_le(result, i)

            # Check for BL instruction (bits 26-31 == 0x25)
            if (instr >> 26) == 0x25
              src = instr
              instr = 0x94000000

              # XZ Utils: pc >>= 2; if (!is_encoder) pc = 0U - pc;
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/simple/arm64.c:56-60
              pc_div_4 = pc >> 2
              pc_for_calc = (0 - pc_div_4) & 0xFFFFFFFF

              instr |= (src + pc_for_calc) & 0x03FFFFFF
              write_uint32_le(result, i, instr)
              # Check for ADRP instruction (bits 25-29 == 0x10000)
            elsif (instr & 0x9F000000) == 0x90000000
              # Extract src from ADRP instruction
              src = ((instr >> 29) & 3) | ((instr >> 3) & 0x001FFFFC)

              # Check if in +/-512 MiB range
              # XZ Utils: if ((src + 0x00020000) & 0x001C0000) continue;
              next if (src + 0x00020000).anybits?(0x001C0000)

              instr &= 0x9000001F

              # XZ Utils: pc >>= 12; if (!is_encoder) pc = 0U - pc;
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/simple/arm64.c:95-96
              pc_div_12 = pc >> 12
              pc_for_calc = (0 - pc_div_12) & 0xFFFFFFFF

              dest = (src + pc_for_calc) & 0xFFFFFFFF
              instr |= (dest & 3) << 29
              instr |= (dest & 0x0003FFFC) << 3
              instr |= (0 - (dest & 0x00020000)) & 0x00E00000

              write_uint32_le(result, i, instr)
            end
          end

          # DEBUG: Show output data
          if ENV["DEBUG_ARM64_BCJ"]
            puts "DEBUG ARM64 BCJ: output (first 32 bytes):"
            puts result[0,
                        32].unpack1("H*").scan(/../).each_slice(16).map { |row|
              row.join(" ")
            }.join("\n")
          end

          result
        end

        # Read an unsigned 32-bit little-endian integer from data
        #
        # @param data [String] Binary data
        # @param offset [Integer] Starting position
        # @return [Integer] Unsigned 32-bit integer
        def read_uint32_le(data, offset)
          bytes = data.byteslice(offset, 4).bytes
          bytes[0] |
            (bytes[1] << 8) |
            (bytes[2] << 16) |
            (bytes[3] << 24)
        end

        # Write an unsigned 32-bit little-endian integer to data
        #
        # @param data [String] Binary data (modified in place)
        # @param offset [Integer] Starting position
        # @param value [Integer] 32-bit integer to write
        # @return [void]
        def write_uint32_le(data, offset, value)
          value &= 0xFFFFFFFF
          data.setbyte(offset, value & 0xFF)
          data.setbyte(offset + 1, (value >> 8) & 0xFF)
          data.setbyte(offset + 2, (value >> 16) & 0xFF)
          data.setbyte(offset + 3, (value >> 24) & 0xFF)
        end

        # Decode LZMA2 data with byte consumption tracking
        #
        # This method is used when compressed_size is not specified in the block header.
        # It uses a CountingInputStream to track how many bytes the LZMA2 decoder consumes.
        #
        # @param all_remaining [String] All remaining data after block header
        # @param filters [Array<Hash>] Filter definitions
        # @return [Array<String, Integer>] Decompressed data and bytes consumed
        def decode_lzma2_with_consumption_tracking(all_remaining:, filters:)
          # Debug: Show first 30 bytes of input data
          if ENV["DEBUG_LZMA2_INPUT"]
            puts "DEBUG LZMA2 INPUT: first 30 bytes:"
            all_remaining.bytes[0, 30].each_with_index do |byte, i|
              printf "  [%2d] 0x%02x (%3d)", i, byte, byte
              puts "" if ((i + 1) % 4).zero?
            end
            puts ""
          end

          input_buffer = CountingInputStream.new(StringIO.new(all_remaining))
          input_buffer.set_encoding(Encoding::BINARY)

          # Get dict_size from LZMA2 filter properties
          # IMPORTANT: For multi-filter chains, find the LZMA2 filter (not just filters[0])
          # The filter chain is in encoding order, so we need to find the LZMA2 filter
          lzma2_filter = filters.find { |f| f[:id] == FILTER_LZMA2 }
          if lzma2_filter.nil?
            raise Omnizip::FormatError,
                  "Unsupported filter chain: LZMA2 filter not found (not supported)"
          end

          properties = lzma2_filter[:properties]
          # XZ spec: max valid prop is 40 (gives ~2GB dict)
          # Cap at 40 to prevent memory exhaustion from malformed files
          dict_size = if properties&.bytesize&.positive?
                        prop = [properties.getbyte(0), MAX_DICT_PROP].min
                        if prop.even?
                          1 << ((prop / 2) + 12)
                        else
                          3 * (1 << (((prop - 1) / 2) + 11))
                        end
                      else
                        8 * 1024 * 1024 # 8MB default
                      end
          dict_size = [dict_size, MAX_DICT_SIZE].min

          # Create LZMA2 decoder with raw_mode for XZ format
          decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input_buffer,
                                                                          raw_mode: true)

          # Set dict_size directly since we skipped property byte reading
          decoder.instance_variable_set(:@dict_size, dict_size)
          decoder.instance_variable_set(:@properties, Omnizip::Algorithms::LZMA2::Properties.new(dict_size))

          # Decode stream
          uncompressed_data = decoder.decode_stream

          # Save decompressed data for filter chain processing
          @decompressed_data = uncompressed_data

          # Return both data and bytes consumed
          [uncompressed_data, input_buffer.bytes_read]
        end

        # Decode LZMA2 data
        #
        # @param compressed_data [String] LZMA2 compressed data
        # @param properties [String, nil] LZMA2 properties byte
        # @return [String] Decompressed data
        def decode_lzma2(compressed_data, properties)
          input_buffer = StringIO.new(compressed_data)
          input_buffer.set_encoding(Encoding::BINARY)

          # For XZ format, LZMA2 data starts with control bytes, not a property byte
          # The filter properties byte contains the dictionary size encoding
          # We need to extract dict_size from properties if available, otherwise use a default

          # Parse properties byte to get dict_size
          # Properties byte format: (pb * 5 + lp) * 9 + lc for LZMA1
          # For LZMA2, it encodes dictionary size directly
          # Format: if d < 40: size = 2^((d/2) + 12) for even d, or 3 * 2^((d-1)/2 + 11) for odd d

          # For now, use a reasonable default since the XZ spec doesn't require
          # the dict_size to be specified in the filter properties for LZMA2
          # The block header filter properties byte (0x08 in our test file) encodes dict_size
          # Using the formula from XZ spec for LZMA2 dict_size encoding:
          # prop 0x08 = 8 means: 2^((8/2) + 12) = 2^16 = 65536 bytes (if even)
          # Wait, let me use the standard formula:
          # If prop is even: dict_size = 2^((prop/2) + 12)
          # If prop is odd: dict_size = 3 * 2^((prop-1)/2 + 11)
          dict_size = if properties&.bytesize&.positive?
                        prop = [properties.getbyte(0), MAX_DICT_PROP].min
                        if prop.even?
                          1 << ((prop / 2) + 12)
                        else
                          3 * (1 << (((prop - 1) / 2) + 11))
                        end
                      else
                        8 * 1024 * 1024 # 8MB default
                      end
          dict_size = [dict_size, MAX_DICT_SIZE].min

          # Create LZMA2 decoder with raw_mode for XZ format
          decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input_buffer,
                                                                          raw_mode: true)

          # Set dict_size directly since we skipped property byte reading
          decoder.instance_variable_set(:@dict_size, dict_size)
          decoder.instance_variable_set(:@properties, Omnizip::Algorithms::LZMA2::Properties.new(dict_size))

          # Decode stream
          decoder.decode_stream
        end

        # Find the end of LZMA2 compressed data by parsing chunks
        #
        # LZMA2 chunk format:
        # - Control byte (1 byte)
        #   - 0x00: End of stream marker (STOP)
        #   - 0x01-0x02: Uncompressed chunk
        #     - Size (2 bytes, big-endian) + 1
        #     - Uncompressed data
        #   - 0x03-0x7F: Compressed chunk (LZMA)
        #     - Properties (1 byte)
        #     - Compressed LZMA data
        #   - 0x80-0xFF: Compressed chunk (LZMA)
        #     - Uncompressed size (2 bytes, big-endian, high 5 bits in control)
        #     - Compressed size (2 bytes, big-endian) + 1
        #     - Properties (1 byte, if control >= 0xC0)
        #     - Compressed LZMA data
        #
        # @param data [String] LZMA2 data to parse
        # @return [Integer] Position where compressed data ends (before check bytes)
        def find_lzma2_compressed_data_end(data)
          pos = 0

          while pos < data.bytesize
            control = data.getbyte(pos)
            pos += 1

            case control
            when 0x00
              # End of stream marker - LZMA2 data ends here
              # Return pos (which includes the end marker, as we've already read it)
              return pos
            when 0x01, 0x02
              # Uncompressed chunk
              # Size encoding: 2 bytes (big-endian) + 1
              size_bytes = data.getbyte(pos) || 0
              pos += 1
              size_bytes = (size_bytes << 8) | (data.getbyte(pos) || 0)
              pos += 1
              uncompressed_size = size_bytes + 1

              # Skip uncompressed data
              pos += uncompressed_size
            when 0x03..0x7F
              # Compressed chunk (LZMA without explicit uncompressed size)
              # Skip properties byte
              pos += 1

              # For compressed data, we need to find where it ends
              # This is complex because the range decoder consumes variable bytes
              # For now, we'll look ahead for patterns that indicate chunk boundaries

              # Look for next chunk start (0x00, 0x01, 0x02, or 0x03-0x7F)
              # But we need to be careful not to mistake data for chunk markers
              #
              # Heuristic: scan forward looking for potential chunk starts
              # A valid chunk start would be followed by valid data structure
              found_next_chunk = false
              scan_pos = pos

              while scan_pos < data.bytesize && !found_next_chunk
                next_byte = data.getbyte(scan_pos)

                # Check if this could be a chunk start
                case next_byte
                when 0x00
                  # End marker - this is the end of the block
                  return scan_pos
                when 0x01, 0x02
                  # Uncompressed chunk - verify it has valid size byte
                  next_next_byte = data.getbyte(scan_pos + 1)
                  if next_next_byte
                    size_hi = (next_byte >> 5)
                    size_lo = next_next_byte
                    uncompressed_size = (size_hi << 8) | size_lo

                    # Check if this size makes sense (not too large)
                    if uncompressed_size <= 1024 && scan_pos + 1 + uncompressed_size <= data.bytesize
                      # Valid uncompressed chunk found
                      return scan_pos
                    end
                  end
                  scan_pos += 1
                when 0x03..0x7F
                  # Another compressed chunk - verify it has properties byte
                  if scan_pos + 1 < data.bytesize
                    # Could be valid - assume this is the next chunk
                    return scan_pos
                  end

                  scan_pos += 1
                else
                  scan_pos += 1
                end
              end

              # If we couldn't find a clear boundary, use current position
              return pos
            when 0x80..0xFF
              # Compressed chunk (LZMA with explicit uncompressed size)
              # Uncompressed size (2 bytes, big-endian)
              pos += 2

              # Compressed size (2 bytes, big-endian) + 1
              compressed_size_hi = data.getbyte(pos) || 0
              pos += 1
              compressed_size_lo = data.getbyte(pos) || 0
              pos += 1
              compressed_size = (compressed_size_hi << 8) | compressed_size_lo
              compressed_size += 1

              # Properties byte (if control >= 0xC0)
              pos += 1 if control >= 0xC0

              # Skip compressed LZMA data
              pos += compressed_size
            else
              # Invalid control byte
              raise Omnizip::FormatError,
                    "Invalid LZMA2 control byte: 0x#{control.to_s(16).upcase}"
            end
          end

          # If we reach here, we've consumed all data
          pos
        end
      end
    end
  end
end
