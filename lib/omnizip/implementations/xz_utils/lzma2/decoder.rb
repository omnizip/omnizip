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

require_relative "../../../error"
require_relative "../../../algorithms/lzma2/constants"
require_relative "../../../algorithms/lzma2/properties"
require_relative "../../../algorithms/lzma/decoder"
require_relative "../../../algorithms/lzma/xz_utils_decoder"

module Omnizip
  module Implementations
    module XZUtils
      module LZMA2
        # XZ Utils LZMA2 decoder implementation.
        #
        # This is the original Decoder moved from algorithms/lzma2/decoder.rb
        # to the new namespace structure.
        class Decoder
          include Omnizip::Algorithms::LZMA2Const

          attr_reader :dict_size

          # Initialize the decoder
          #
          # @param input [IO] Input stream of compressed data
          # @param options [Hash] Decoding options
          # @option options [Boolean] :raw_mode If true, skip property byte reading (for XZ format)
          # @option options [Integer] :dict_size Dictionary size to use (required for raw_mode)
          def initialize(input, options = {})
            @input = input
            @options = options
            @raw_mode = options[:raw_mode] || false

            if @raw_mode
              # In raw_mode (XZ format), property byte is provided by caller
              # Only dict_size comes from the XZ filter properties
              @dict_size = options[:dict_size] || (8 * 1024 * 1024)
              @properties = Omnizip::Algorithms::LZMA2::Properties.new(@dict_size)
            else
              read_property_byte
            end
          end

          # Decode a compressed stream
          #
          # XZ Utils pattern (lzma2_decoder.c):
          # - LZMA decoder is created ONCE and reused across all chunks
          # - State (dictionary, probability models) persists between chunks
          # - Reset only when control byte indicates new properties (control >= 0xC0)
          #
          # @return [String] Decompressed data
          def decode_stream
            output = []

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: decode_stream - starting..."
              # Note: Can't peek at input without consuming, skip debug output
            end

            # XZ Utils pattern: Create LZMA decoder ONCE (lzma2_decoder_init)
            # The decoder will be reused across all chunks
            @lzma_decoder = nil
            @need_properties = true # First LZMA chunk needs properties (XZ Utils line 45)
            @need_dictionary_reset = true # First chunk must reset dictionary (XZ Utils line 43)

            chunk_num = 0
            loop do
              control = read_control_byte

              # puts "DEBUG LZMA2 chunk ##{chunk_num}: control=0x#{control.to_s(16)}" if ENV["LZMA2_DEBUG"]

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decode_stream - chunk ##{chunk_num}, control=0x#{control.to_s(16)}"
              end

              break if control == CONTROL_END

              # XZ Utils pattern (lzma2_decoder.c:75-82):
              # Dictionary reset is needed if control >= 0xE0 or control == 1
              # If dictionary reset is needed but control doesn't do it, error
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:75-82
              if control >= 0xE0 || control == CONTROL_UNCOMPRESSED_RESET
                @need_properties = true
                @need_dictionary_reset = true
              elsif @need_dictionary_reset
                raise Omnizip::FormatError,
                      "LZMA2 dictionary reset required but not performed (control=0x#{control.to_s(16).upcase})"
              end

              # XZ Utils pattern (lzma2_decoder.c:121-126):
              # Perform dictionary reset if needed
              # For control >= 0xE0 or control == 1, need_dictionary_reset is set above
              # and we perform the reset here, then clear the flag
              # IMPORTANT: Only UNCOMPRESSED chunks with reset (control == 1) should
              # suppress output. Compressed chunks with reset (control >= 0x80) should
              # ALWAYS produce output - the dictionary reset happens before decoding.
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:121-127
              false
              if @need_dictionary_reset
                @need_dictionary_reset = false
                # For uncompressed chunks with reset (control == 1), output is suppressed
                # For compressed chunks (control >= 0x80), output is always produced
                (control == CONTROL_UNCOMPRESSED_RESET)
                # Note: Dictionary reset will be handled by the LZMA decoder
                # based on the control byte
              end

              # XZ Utils pattern (lzma2_decoder.c:84-110):
              # For LZMA chunks (control >= 0x80), validate properties requirements
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:98-99
              if control >= 0x80
                if control >= 0xC0
                  # New properties present - properties will be read below
                  @need_properties = false
                elsif @need_properties
                  # LZMA chunk without properties but properties are needed
                  # This happens after dictionary reset when next chunk must have properties
                  raise Omnizip::FormatError,
                        "LZMA2 properties required but not provided (control=0x#{control.to_s(16).upcase})"
                end
              end

              chunk_data = decode_chunk(control, chunk_num)

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decode_stream - chunk ##{chunk_num} produced #{chunk_data.bytesize} bytes"
              end

              # XZ Utils pattern: Uncompressed chunks ALWAYS produce output
              # Dictionary reset chunks (control == 1) initialize the dictionary
              # with the chunk data, then the dictionary is flushed to output
              # So we should NEVER skip output for valid chunks
              # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:121-127
              output << chunk_data
              chunk_num += 1
            end

            if ENV["LZMA2_DEBUG"]
              total_size = output.sum(&:bytesize)
              warn "DEBUG: decode_stream - finished, total chunks=#{chunk_num}, total_size=#{total_size}"
            end

            output.join.force_encoding("ASCII-8BIT")
          end

          private

          # Read and parse LZMA2 property byte
          #
          # @return [void]
          # @raise [Omnizip::FormatError] If property byte is invalid
          def read_property_byte
            prop_byte = @input.getbyte
            raise Omnizip::FormatError, "Invalid LZMA2 header" if prop_byte.nil?

            @properties = Omnizip::Algorithms::LZMA2::Properties.from_byte(prop_byte)
            @dict_size = @properties.actual_dict_size
          end

          # Read control byte
          #
          # @return [Integer] Control byte value
          # @raise [Omnizip::IOError] If stream ends unexpectedly
          def read_control_byte
            byte = @input.getbyte
            raise Omnizip::IOError, "Unexpected end of stream" if byte.nil?

            byte
          end

          # Decode chunk based on control byte
          #
          # XZ Utils pattern (lzma2_decoder.c:75-102):
          # - control >= 0xE0 or control == 1: Dictionary reset + properties needed
          # - control >= 0xC0: State reset + properties
          # - control >= 0xA0: State reset only
          # - control >= 0x80: LZMA chunk (no reset)
          # - control == 0x01 or 0x02: Uncompressed chunk
          # - control > 2 and < 0x80: INVALID (LZMA2_DATA_ERROR)
          #
          # @param control [Integer] Control byte
          # @param chunk_num [Integer] Chunk sequence number
          # @return [String] Decoded chunk data
          def decode_chunk(control, chunk_num)
            if ENV["LZMA2_DEBUG"]
              pos = @input.respond_to?(:pos) ? @input.pos : "N/A"
              warn "DEBUG: decode_chunk - chunk=#{chunk_num}, control=0x#{control.to_s(16)}, pos=#{pos}"
            end

            # XZ Utils pattern (lzma2_decoder.c:138-140):
            # Invalid control values: control > 2 and < 0x80 are invalid
            # Reference: /Users/mulgogi/src/external/xz/src/liblzma/lzma/lzma2_decoder.c:138-140
            if control > 2 && control < 0x80
              raise Omnizip::FormatError,
                    "Invalid LZMA2 control byte: 0x#{control.to_s(16).upcase} " \
                    "(valid ranges: 0x00-0x02, 0x80-0xFF)"
            end

            if uncompressed_chunk?(control)
              decode_uncompressed_chunk(control)
            else
              decode_compressed_chunk(control, chunk_num)
            end
          end

          # Check if control byte indicates uncompressed chunk
          #
          # @param control [Integer] Control byte
          # @return [Boolean] True if uncompressed
          def uncompressed_chunk?(control)
            [CONTROL_UNCOMPRESSED_RESET,
             CONTROL_UNCOMPRESSED].include?(control)
          end

          # Decode uncompressed chunk
          #
          # XZ Utils pattern (lzma2_decoder.c:193-200):
          # - Copy from input to the dictionary as is using dict_write()
          # - This ensures subsequent compressed chunks can reference the data
          # - If LZMA decoder exists, add data to dictionary directly
          # - If LZMA decoder doesn't exist, store data in @uncompressed_buffer
          #
          # @param control [Integer] Control byte
          # @return [String] Uncompressed data
          def decode_uncompressed_chunk(_control)
            # Read uncompressed size (2 bytes, big-endian)
            size = read_size_bytes(2) + 1

            if ENV["LZMA2_DEBUG"]
              pos_before = @input.respond_to?(:pos) ? @input.pos : "N/A"
              warn "DEBUG: decode_uncompressed_chunk - size=#{size}, pos_before=#{pos_before}"
            end

            # Read uncompressed data
            data = @input.read(size)

            if ENV["LZMA2_DEBUG"]
              pos_after = @input.respond_to?(:pos) ? @input.pos : "N/A"
              actual_size = data&.bytesize || 0
              warn "DEBUG: decode_uncompressed_chunk - expected=#{size}, actual=#{actual_size}, pos_after=#{pos_after}"
              warn "DEBUG: decode_uncompressed_chunk - data_nil=#{data.nil?}"
            end

            if data.nil? || data.bytesize != size
              raise Omnizip::IOError,
                    "Unexpected end of stream"
            end

            # XZ Utils pattern: Copy from input to the dictionary as is.
            # Reference: lzma2_decoder.c:195 - dict_write(dict, in, in_pos, in_size, &coder->compressed_size)
            #
            # If the LZMA decoder exists, add the data to its dictionary directly
            # Otherwise, store it in @uncompressed_buffer for later use
            if @lzma_decoder
              # LZMA decoder exists - add data to its dictionary
              @lzma_decoder.add_to_dictionary(data)
              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decode_uncompressed_chunk - Added #{data.bytesize} bytes to LZMA decoder's dictionary"
              end
            else
              # LZMA decoder doesn't exist yet - store data for later
              # This will be added to the dictionary when the first compressed chunk arrives
              @uncompressed_buffer ||= String.new(encoding: "ASCII-8BIT")
              @uncompressed_buffer << data
              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decode_uncompressed_chunk - Stored #{data.bytesize} bytes in uncompressed_buffer (total #{@uncompressed_buffer.bytesize} bytes)"
              end
            end

            data
          end

          # Decode compressed chunk
          #
          # XZ Utils pattern (lzma2_decoder.c:84-103, 154-161, 163-191):
          # - control >= 0xC0: New properties present, call decoder.reset()
          # - control >= 0xA0: State reset only
          # - control >= 0x80: LZMA chunk with explicit uncompressed/compressed size
          # - control 0x03-0x7F: INVALID (rejected in decode_chunk)
          # - LZMA decoder is created once and reused across all chunks
          #
          # DEBUG: Trace chunk decompression
          dict_full_before = begin
            @lzma_decoder.instance_variable_get(:@dict_full)
          rescue StandardError
            "nil"
          end
          warn "DEBUG: decode_compressed_chunk START (control=#{control}, dict_full=#{dict_full_before})" if dict_full_before.is_a?(Integer) && dict_full_before >= 210
          # @param control [Integer] Control byte
          # @param chunk_num [Integer] Chunk sequence number
          # @return [String] Decompressed data
          def decode_compressed_chunk(control, chunk_num)
            if control >= 0x80
              # Compressed chunk with explicit uncompressed/compressed size
              # Read uncompressed size (2 bytes, big-endian)
              # High 3 bits are in bits 2-0 of the control byte (bits 19-17 of uncompressed size)
              uncompressed_low_bytes = [@input.getbyte, @input.getbyte]
              uncompressed_low = (uncompressed_low_bytes[0] << 8) | uncompressed_low_bytes[1]
              # XZ Utils lzma2_decoder.c:87: (control & 0x1F) << 16, then += each byte
              # High 5 bits of (uncompressed_size - 1) are in bits 4-0 of control byte
              uncompressed_high = control & 0x1F
              uncompressed_size = (uncompressed_high << 16) + uncompressed_low + 1

              # Read compressed size (2 bytes, big-endian)
              compressed_size = read_size_bytes(2) + 1
            else
              # This should never be reached because control bytes 0x03-0x7F are
              # rejected in decode_chunk() before this method is called.
              # Control bytes < 0x80 should only be 0x01 or 0x02, which are
              # handled by decode_uncompressed_chunk(), not this method.
              raise Omnizip::FormatError,
                    "Invalid LZMA2 control byte: 0x#{control.to_s(16).upcase} " \
                    "(control < 0x80 but not 0x01 or 0x02)"
            end
            # Note: For control >= 0x80, compressed_data will be read below.
            # For control < 0x80 (unreachable), this method raises above.

            # Read properties byte
            # LZMA2 format: Properties byte is ONLY present for control >= 0xC0
            # For control >= 0xA0 but < 0xC0, use default properties (no properties byte)
            # For control < 0xA0 (but >= 0x80), use previous properties (no properties byte)
            # Reference: XZ Utils lzma2_decoder.c:92-96, 154-160
            if control >= 0xC0
              # New properties present - read properties byte
              properties = @input.getbyte
              if properties.nil?
                raise Omnizip::IOError,
                      "Unexpected end of stream"
              end
            else
              # No properties byte for control >= 0xA0 but < 0xC0
              # Use default properties for LZMA2
              properties = nil
            end

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: decode_compressed_chunk - control=0x#{control.to_s(16)}"
              # Note: control >= 0x80 is guaranteed here since:
              # 1. decode_chunk() rejects control bytes 0x03-0x7F
              # 2. decode_uncompressed_chunk() handles control bytes 0x01-0x02
              # So only control >= 0x80 reaches this method
              warn "  uncompressed_size: #{uncompressed_size}"
              warn "  compressed_size: #{compressed_size}"
              warn "  properties: #{properties&.to_s(16)}"
            end

            if control >= 0x80
              if ENV["LZMA2_DEBUG"]
                pos_before = @input.respond_to?(:pos) ? @input.pos : "N/A"
                warn "DEBUG: decode_compressed_chunk - uncompressed=#{uncompressed_size}, compressed=#{compressed_size}, properties=#{properties&.to_s(16)}, pos_before=#{pos_before}"
                warn "DEBUG: @input.respond_to?(:pos)=#{@input.respond_to?(:pos)}, @input.class=#{@input.class}"
              end

              # Read compressed data
              compressed_data = @input.read(compressed_size)
              if ENV["LZMA2_DEBUG"]
                @input.respond_to?(:pos) ? @input.pos : "N/A"
                actual_size = compressed_data&.bytesize || 0
                warn "DEBUG: decode_compressed_chunk - expected=#{compressed_size}, actual=#{actual_size}"
                warn "DEBUG: compressed_data hex: #{compressed_data.bytes.map do |b|
                  "0x#{b.to_s(16).rjust(2, '0')}"
                end.join(' ')}"
              end
              if compressed_data.nil? || compressed_data.bytesize != compressed_size
                if ENV["LZMA2_DEBUG"]
                  actual_size = compressed_data&.bytesize || 0
                  warn "DEBUG: decode_compressed_chunk - FAILED - expected=#{compressed_size}, actual=#{actual_size}"
                end
                raise Omnizip::IOError, "Unexpected end of stream"
              end
            end

            # Decompress using LZMA
            # Pass control byte to handle decoder creation/reset logic
            decompress_lzma_chunk(compressed_data, uncompressed_size, properties,
                                  control, chunk_num)
          end

          # Decompress LZMA chunk
          #
          # XZ Utils pattern (lzma2_decoder.c:92-103, 154-191):
          # - Create LZMA decoder on first chunk or when control >= 0xC0
          # - Call decoder.reset() when new properties are present (control >= 0xC0)
          # - Reuse decoder state across chunks (preserves probability models)
          # - Reset range decoder between chunks (lzma_decoder.c:1014-1017)
          #
          # @param compressed_data [String] Compressed data (no LZMA header)
          # @param expected_size [Integer] Expected decompressed size (from LZMA2 chunk header)
          # @param properties [Integer, nil] LZMA properties byte from LZMA2 chunk (if present)
          # @param control [Integer] LZMA2 control byte for this chunk
          # @param chunk_num [Integer] Chunk sequence number
          # @return [String] Decompressed data
          def decompress_lzma_chunk(compressed_data, expected_size, properties,
                                    control, chunk_num)
            # puts "\nDEBUG decompress_lzma_chunk: chunk=#{chunk_num}, expected_size=#{expected_size}, control=0x#{control.to_s(16)}" if ENV["LZMA2_DEBUG"]

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: decompress_lzma_chunk - expected_size=#{expected_size}, compressed_size=#{compressed_data.bytesize}, properties=#{properties&.to_s(16)}"
              warn "DEBUG: @expected_uncompressed_size=#{@expected_uncompressed_size}" if defined?(@expected_uncompressed_size)
            end

            # XZ Utils pattern (lzma2_decoder.c:140-141):
            # Pass the chunk's uncompressed_size to the LZMA decoder.
            # The block header's uncompressed_size is for validation only.
            # For simple compressed chunks (control < 0x80), expected_size is nil,
            # which means decode until LZMA end-of-stream marker.
            lzma_uncompressed_size = expected_size || 0xFFFFFFFFFFFFFFFF # UNKNOWN = decode until EOS

            # Decode lc, lp, pb from LZMA chunk properties byte
            # In XZ format, the chunk properties byte is inside the compressed chunk
            # and contains: (pb * 9 * 5) + (lp * 9) + lc
            # Reference: /tmp/xz-source/src/liblzma/lzma/lzma_decoder.c:1199-1209
            if properties && properties >= 0
              # Decode lc, lp, pb from chunk properties byte using XZ Utils formula
              pb = properties / (9 * 5)
              remainder = properties - (pb * 9 * 5)
              lp = remainder / 9
              lc = remainder - (lp * 9)
            else
              # Default values when no properties present
              # XZ Utils defaults: lc=3, lp=0, pb=2
              lc = 3
              lp = 0
              pb = 2
            end

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: decompress_lzma_chunk - lc=#{lc}, lp=#{lp}, pb=#{pb}, properties=#{properties&.to_s(16)}"
            end

            # XZ Utils pattern: Create/reuse LZMA decoder across chunks
            # lzma2_decoder.c:92-103, 154-161: Handle decoder creation and reset
            #
            # IMPORTANT: We need to handle the case where the first chunk(s) are
            # uncompressed. The uncompressed data must be added to the LZMA decoder's
            # dictionary BEFORE we create the decoder, so we'll pass it as preloaded data.
            if chunk_num.zero? || !@lzma_decoder
              # First chunk - create LZMA decoder in lzma2_mode
              # NO LZMA HEADER - pass compressed data directly
              # XZ Utils: lzma_lz_decoder_create + lzma_lzma_decoder_create
              input_buffer = StringIO.new(compressed_data)
              input_buffer.set_encoding("ASCII-8BIT")

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: input_buffer created, pos=#{input_buffer.pos}, size=#{compressed_data.bytesize}"
                warn "DEBUG: compressed_data bytes (first 20): #{compressed_data[0..20].bytes.map do |b|
                  b.to_s(16).rjust(2, '0')
                end.join(' ')}"
              end

              # Check if we have uncompressed data to preload into the dictionary
              preloaded_data = @uncompressed_buffer if @uncompressed_buffer && !@uncompressed_buffer.empty?

              @lzma_decoder = Omnizip::Algorithms::XzUtilsDecoder.new(input_buffer,
                                                                      lzma2_mode: true,
                                                                      lc: lc,
                                                                      lp: lp,
                                                                      pb: pb,
                                                                      dict_size: @dict_size,
                                                                      uncompressed_size: lzma_uncompressed_size,
                                                                      preloaded_data: preloaded_data) # Pass uncompressed data to preload

              # Clear uncompressed buffer after passing to decoder
              @uncompressed_buffer = nil if preloaded_data

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decompress_lzma_chunk - Created new LZMA decoder (lzma2_mode)#{" with #{preloaded_data.bytesize} bytes of preloaded data" if preloaded_data}"
              end
            else
              # Subsequent chunks - reuse decoder, reset if needed
              # XZ Utils lzma2_decoder.c:92-96, 154-161

              # Determine if dictionary should be preserved
              # Use the same logic as at line 414 for consistency
              # XZ Utils LZMA2 control byte decoding (lzma2_decoder.c:75-79):
              # - control >= 0xE0: LZMA2 compressed + reset dictionary + properties byte present
              # - control = 0x01: end of chunk marker
              # XZ Utils sets need_dictionary_reset = true ONLY for control >= 0xE0 || control == 1
              # Therefore, dict_reset is ONLY called for control >= 0xE0 || control == 1
              # - control = 0xC0: LZMA2 compressed + state reset + default properties (NO dict reset!)
              # - control < 0x80: LZMA2 uncompressed
              # - 0x80 <= control < 0xC0: LZMA2 compressed + preserve dictionary
              # Note: chunk_num >= 1 here (not the first chunk)
              preserve_dict = !(control >= 0xE0 || control == 1)

              if control >= 0xC0
                # New properties present - reset decoder with new properties
                @lzma_decoder.reset(new_lc: lc, new_lp: lp, new_pb: pb,
                                    preserve_dict: preserve_dict)

                # Pass compressed data directly (NO LZMA HEADER)
                input_buffer = StringIO.new(compressed_data)
                input_buffer.set_encoding("ASCII-8BIT")

                @lzma_decoder.set_input(input_buffer)

                if ENV["LZMA2_DEBUG"]
                  warn "DEBUG: decompress_lzma_chunk - Reset LZMA decoder with new properties (preserve_dict=#{preserve_dict})"
                end
              elsif control >= 0xA0
                # State reset only (no new properties)
                # IMPORTANT: XZ Utils source code (lzma2_decoder.c:107-109) shows that
                # for control >= 0xA0, it calls coder->lzma.reset(), which resets
                # rep distances to 0 (see lzma_decoder.c:1071-1074).
                #
                # A rep match with distance=0 is valid - it means "copy the last byte"
                # (distance 0 from the current position, i.e., the byte just written).
                decoder_dict_full = begin
                  @lzma_decoder.instance_variable_get(:@dict_full)
                rescue StandardError
                  nil
                end
                if ENV["LZMA2_DEBUG"] || (decoder_dict_full && decoder_dict_full >= 220 && decoder_dict_full <= 230)
                  warn "DEBUG: decompress_lzma_chunk - Calling reset with preserved dict (control=#{control}, dict_full=#{decoder_dict_full})"
                end
                @lzma_decoder.reset(preserve_dict: preserve_dict)

                # Pass compressed data directly (NO LZMA HEADER)
                input_buffer = StringIO.new(compressed_data)
                input_buffer.set_encoding("ASCII-8BIT")

                @lzma_decoder.set_input(input_buffer)

                if ENV["LZMA2_DEBUG"]
                  warn "DEBUG: decompress_lzma_chunk - After set_input, checking range_decoder..."
                  # Check if the decoder has a range_decoder variable
                  if @lzma_decoder.instance_variable_defined?(:@range_decoder)
                    range_decoder = @lzma_decoder.instance_variable_get(:@range_decoder)
                    if range_decoder
                      warn "  range_decoder exists: code=0x#{range_decoder.instance_variable_get(:@code).to_s(16)}, range=0x#{range_decoder.instance_variable_get(:@range).to_s(16)}, init_bytes_remaining=#{range_decoder.instance_variable_get(:@init_bytes_remaining)}"
                    else
                      warn "  range_decoder is nil"
                    end
                  else
                    warn "  @range_decoder not defined yet"
                  end
                end
              else
                # For control >= 0x80 but < 0xA0: No reset
                # Pass compressed data directly (NO LZMA HEADER)
                input_buffer = StringIO.new(compressed_data)
                input_buffer.set_encoding("ASCII-8BIT")

                @lzma_decoder.set_input(input_buffer)
              end

              # XZ Utils: Set uncompressed size for each chunk (lzma2_decoder.c:140-141)
              @lzma_decoder.set_uncompressed_size(lzma_uncompressed_size,
                                                  allow_eopm: false)

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: decompress_lzma_chunk - Reusing LZMA decoder, set uncompressed_size=#{lzma_uncompressed_size}"
              end
            end

            # For first chunk or when control >= 0xE0 or control == 1, reset dictionary (preserve_dict = false)
            # For other chunks with control < 0xE0 and control != 1, preserve dictionary
            # XZ Utils LZMA2 control byte decoding (lzma2_decoder.c:75-79):
            # - control >= 0xE0: LZMA2 compressed + reset dictionary + properties byte present
            # - control = 0x01: end of chunk marker
            # XZ Utils sets need_dictionary_reset = true ONLY for control >= 0xE0 || control == 1
            # Therefore, dict_reset is ONLY called for control >= 0xE0 || control == 1
            # - control = 0xC0: LZMA2 compressed + state reset + default properties (NO dict reset!)
            # - control < 0x80: LZMA2 uncompressed
            # - 0x80 <= control < 0xC0: LZMA2 compressed + preserve dictionary
            preserve_dictionary = chunk_num.zero? ? false : !(control >= 0xE0 || control == 1)

            decompressed = @lzma_decoder.decode_stream(nil,
                                                       preserve_dict: preserve_dictionary,
                                                       check_rc_finished: false)

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: decompress_lzma_chunk - expected=#{lzma_uncompressed_size}, got=#{decompressed.bytesize}"
            end

            # Verify size matches expected
            if ENV["LZMA2_DEBUG"]
              # puts "DEBUG: Size check - decompressed=#{decompressed.bytesize}, expected=#{lzma_uncompressed_size}"
            end
            if decompressed.bytesize != lzma_uncompressed_size
              puts "DEBUG: Size mismatch - decompressed=#{decompressed.bytesize}, expected=#{lzma_uncompressed_size}"
              raise Omnizip::DecompressionError, "Decompressed size mismatch: expected #{lzma_uncompressed_size}, " \
                                                 "got #{decompressed.bytesize}"
            end

            decompressed
          end

          # Build LZMA header for decompression
          #
          # @param uncompressed_size [Integer] Expected size after decompression
          # @param properties [Integer, nil] LZMA properties byte (lc/lp/pb encoding) from LZMA2 chunk
          # @return [String] LZMA header (13 bytes)
          def build_lzma_header(uncompressed_size, properties = nil)
            header = String.new(encoding: "ASCII-8BIT")

            # The properties byte from LZMA2 encodes lc, lp, pb (not dictionary size!)
            # Decode using XZ Utils formula from lzma_lzma_lclppb_decode:
            # pb = byte / (9 * 5)
            # byte -= pb * 9 * 5
            # lp = byte / 9
            # lc = byte - lp * 9
            if properties && properties >= 0
              prop_byte = properties
              pb = prop_byte / (9 * 5)
              remainder = prop_byte - (pb * 9 * 5)
              lp = remainder / 9
              lc = remainder - (lp * 9)

              props = lc + (lp * 9) + (pb * 9 * 5)

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: build_lzma_header - properties=0x#{prop_byte.to_s(16)} -> lc=#{lc}, lp=#{lp}, pb=#{pb}, props=0x#{props.to_s(16)}"
              end
            else
              # Default values when no properties present
              lc = 0
              lp = 0
              pb = 0

              if ENV["LZMA2_DEBUG"]
                warn "DEBUG: build_lzma_header - no properties, using defaults lc=0, lp=0, pb=0"
              end
            end

            # Calculate props encoding (props encoding is calculated the same way for both cases)
            props = lc + (lp * 9) + (pb * 9 * 5)

            header << [props].pack("C")

            # Dictionary size from @dict_size (set during initialization from LZMA2 filter properties)
            header << [@dict_size].pack("V")

            # Uncompressed size (8 bytes, little-endian)
            header << [uncompressed_size].pack("Q<")

            header
          end

          # Read size bytes in big-endian order
          #
          # @param num_bytes [Integer] Number of bytes to read
          # @return [Integer] Size value
          def read_size_bytes(num_bytes)
            size = 0
            num_bytes.times do
              byte = @input.getbyte
              raise Omnizip::IOError, "Unexpected end of stream" if byte.nil?

              size = (size << 8) | byte
            end
            size
          end

          # Ensure LZMA decoder exists
          # Creates a decoder with default properties if one doesn't exist yet
          # This is needed for uncompressed chunks that come before the first compressed chunk
          def ensure_lzma_decoder_exists
            return if @lzma_decoder

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: ensure_lzma_decoder_exists - Creating LZMA decoder for uncompressed chunk"
            end

            # Create LZMA decoder with default properties (lc=3, lp=0, pb=2)
            # These defaults match XZ Utils and ensure compatibility
            @lzma_decoder = Omnizip::Algorithms::XzUtilsDecoder.new(
              StringIO.new(""), # Empty input for now
              lzma2_mode: true,
              lc: 3,
              lp: 0,
              pb: 2,
              dict_size: @dict_size,
              uncompressed_size: 0xFFFFFFFFFFFFFFFF, # Unknown size
            )

            # Initialize dictionary buffer explicitly since we're not calling decode_stream
            # This mimics the initialization done in decode_stream
            dict_buf_size = @dict_size + Omnizip::Algorithms::LZMA::XzUtilsDecoder::LZ_DICT_INIT_POS
            @lzma_decoder.instance_variable_set(:@dict_buf,
                                                Array.new(dict_buf_size, 0))
            @lzma_decoder.instance_variable_set(:@pos, Omnizip::Algorithms::LZMA::XzUtilsDecoder::LZ_DICT_INIT_POS)
            @lzma_decoder.instance_variable_set(:@dict_full, 0)
            @lzma_decoder.instance_variable_set(:@has_wrapped, false)

            # Initialize rep distances
            @lzma_decoder.instance_variable_set(:@rep0, 0)
            @lzma_decoder.instance_variable_set(:@rep1, 0)
            @lzma_decoder.instance_variable_set(:@rep2, 0)
            @lzma_decoder.instance_variable_set(:@rep3, 0)

            # Initialize state machine
            @lzma_decoder.instance_variable_set(:@state, Omnizip::Algorithms::LZMA::SdkStateMachine.new)

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: ensure_lzma_decoder_exists - Created LZMA decoder with lc=3, lp=0, pb=2, dict_size=#{@dict_size}"
              warn "DEBUG: ensure_lzma_decoder_exists - Initialized dict_buf_size=#{dict_buf_size}, pos=#{Omnizip::Algorithms::LZMA::XzUtilsDecoder::LZ_DICT_INIT_POS}"
            end
          end
        end
      end
    end
  end
end
