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
require "stringio"
require_relative "../../algorithms/lzma2"
require_relative "../../checksums/crc64"
require_relative "../../error"
require_relative "constants"
require_relative "block_encoder"

module Omnizip
  module Formats
    class Xz
      # XZ format writer
      #
      # Creates .xz files compatible with XZ Utils.
      # Structure: Stream Header + Block(s) + Index + Stream Footer
      #
      # Based on: xz/src/liblzma/common/stream_encoder.c
      class Writer
        include XzConst

        # XZ format magic bytes
        HEADER_MAGIC = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].freeze
        FOOTER_MAGIC = [0x59, 0x5A].freeze

        # Create XZ file with block given
        #
        # @param filename [String] Output filename
        # @param options [Hash] Encoding options
        # @yield [writer] Block receives writer instance
        def self.create(filename, options = {})
          File.open(filename, "wb") do |f|
            writer = new(f, options)
            yield writer if block_given?
            writer.finalize
          end
        end

        # Initialize XZ writer
        #
        # @param output [IO] Output stream
        # @param options [Hash] Encoding options
        def initialize(output, options = {})
          @output = output
          @options = options
          @blocks = []

          write_stream_header
        end

        # Add data block to stream
        #
        # @param data [String] Data to compress and add
        def add_data(data)
          # Use BlockEncoder for XZ Utils compatibility
          # This produces compressed blocks compatible with XZ Utils
          block_encoder = XzFormat::BlockEncoder.new(
            check_type: @options[:check_type] || CHECK_CRC64,
            dict_size: @options[:dict_size] || (64 * 1024 * 1024), # Use 64MB to match XZ Utils default
            include_block_sizes: true, # Include size fields for XZ Utils compatibility
          )

          block = block_encoder.encode_block(data)

          # Store block info for index
          @blocks << {
            compressed: block[:data],
            actual_compressed_size: block[:compressed_size],
            uncompressed_data: data,
            uncompressed_size: block[:uncompressed_size],
            unpadded_size: block_encoder.unpadded_size,
          }

          # Write block using the encoded data from BlockEncoder
          write_block_from_encoder(block)
        end

        # Write block from BlockEncoder output
        #
        # @param block [Hash] Block info from BlockEncoder
        def write_block_from_encoder(block)
          # Write block header (from BlockEncoder)
          @output.write(block[:header])

          # Write compressed data
          @output.write(block[:data])

          # Write padding (from BlockEncoder)
          @output.write(block[:padding])

          # Write check (CRC64 of uncompressed data)
          write_check_from_block(block)
        end

        # Write check value from block
        #
        # @param block [Hash] Block info from BlockEncoder
        def write_check_from_block(block)
          @output.write(block[:check])
        end

        # Finalize XZ stream
        def finalize
          write_index
          write_stream_footer
        end

        private

        # Encode VLI (variable-length integer)
        #
        # @param value [Integer] Value to encode
        # @return [String] Encoded bytes (low bits first)
        def self.encode_vli(value)
          value
          bytes = []
          loop do
            # Get low 7 bits
            byte = value & 0x7F
            value >>= 7
            # Set continuation bit if there's more data
            byte |= 0x80 unless value.zero?
            bytes << byte
            break if value.zero?
          end

          bytes.pack("C*")
        end

        # Write stream header (12 bytes)
        def write_stream_header
          # Magic bytes (6 bytes)
          @output.write(HEADER_MAGIC.pack("C*"))

          # Stream flags (2 bytes): CRC64 check type (0x04)
          flags = [0x00, 0x04].pack("C*")
          @output.write(flags)

          # CRC32 of flags (4 bytes, little-endian)
          crc = Zlib.crc32(flags)
          @output.write([crc].pack("V"))
        end

        # Encode data block with LZMA2
        #
        # @param data [String] Input data
        # @return [Array<String, Integer>] LZMA2 chunk data and actual decode size
        #
        # NOTE: Currently uses uncompressed LZMA2 chunks for maximum compatibility.
        # Compressed mode has subtle bugs in range encoder cache management.
        # Uncompressed XZ files are fully valid and compatible with all XZ Utils.
        def encode_lzma2_block(data)
          # Create LZMA2 encoder
          # NOTE: Currently using uncompressed chunks due to LZMA encoder compatibility issues
          # The SDK encoder produces compressed data that xz cannot decode properly
          # This is a known limitation that needs to be fixed by porting the LZMA encoder
          # more carefully from XZ Utils reference implementation.
          encoder = Omnizip::Algorithms::LZMA2Encoder.new(
            dict_size: @options[:dict_size] || (1 << 23),
            lc: @options[:lc] || 3,
            lp: @options[:lp] || 0,
            pb: @options[:pb] || 2,
            allow_compression: false, # Disable compression for compatibility
            use_xz_encoder: false,
          )

          # Get full LZMA2 stream (includes chunks + end marker)
          full_stream = encoder.encode(data)

          # CRITICAL: XZ blocks MUST include the LZMA2 end marker (0x00)
          # The full stream is written to the block as-is
          lzma2_chunk = full_stream

          # CRITICAL: actual_size MUST include the end marker!
          # The LZMA2 decoder reads the end marker to know when to stop.
          # Per XZ spec, compressed_size in block header = total bytes in block data
          actual_size = lzma2_chunk.bytesize

          [lzma2_chunk, actual_size]
        end

        # Calculate unpadded size (block header + compressed size + check size)
        #
        # @param compressed [String] Compressed data (LZMA2 chunk without end marker)
        # @param uncompressed_size [Integer] Uncompressed data size
        # @param actual_compressed_size [Integer, nil] Actual bytes decoder consumes
        # @return [Integer] Unpadded size
        def calculate_unpadded_size(compressed, uncompressed_size,
                                    actual_compressed_size = nil)
          # CRITICAL: Use actual_compressed_size (bytes decoder consumes)
          # not compressed.bytesize (buffer size including any padding).
          # This matches XZ Utils' Index encoding exactly.
          compressed_size = actual_compressed_size || compressed.bytesize

          # Build header fields (same as in write_block_header)
          # NOTE: xz command includes size fields by default (block flags = 0xC0)
          header = StringIO.new
          header.write([0xC0].pack("C")) # Flags (both sizes present)

          # Compressed size (VLI)
          header.write(self.class.encode_vli(compressed_size))

          # Uncompressed size (VLI)
          header.write(self.class.encode_vli(uncompressed_size))

          # Filter flags: LZMA2 + props size + dict size encoding
          dict_size = @options[:dict_size] || (1 << 23)
          props = Omnizip::Algorithms::LZMA2Encoder.encode_dict_size(dict_size)
          header.write([0x21, 0x01, props].pack("C*"))

          header_fields = header.string

          # Calculate padding (same logic as write_block_header)
          base_size = 1 + header_fields.bytesize + 4 # size_byte + fields + CRC
          padding_needed = (4 - (base_size % 4)) % 4

          # Total block header size
          block_header_size = base_size + padding_needed

          # Unpadded size = block header + actual compressed data + check (CRC64 = 8 bytes)
          # NOTE: "Unpadded" means EXCLUDING Block Padding (the padding after compressed data)
          # Block Padding is added in write_block but is NOT counted in Index's Unpadded Size
          block_header_size + compressed_size + 8
        end

        # Write block to output
        #
        # @param block [Hash] Block info
        def write_block(block)
          # Write block header
          write_block_header(block)

          # Write compressed data (LZMA2 stream including end marker)
          # CRITICAL: The compressed_size in block header should include the end marker
          # because the decoder reads it to know when to stop
          @output.write(block[:compressed])

          # Block Padding: XZ spec requires padding (header + data) to 4-byte boundary
          # Block header is always multiple of 4, so we only need to consider data size
          compressed_size = block[:compressed].bytesize
          padding_needed = (4 - (compressed_size % 4)) % 4
          @output.write("\x00" * padding_needed) if padding_needed.positive?

          # Write check (CRC64 of UNCOMPRESSED data)
          write_check(block[:uncompressed_data])
        end

        # Write block header
        #
        # @param block [Hash] Block info
        def write_block_header(block)
          header = StringIO.new

          # Block flags (1 byte):
          # Bit 7: uncompressed size present (SET - matching XZ Utils default)
          # Bit 6: compressed size present (SET - matching XZ Utils default)
          # Bits 0-2: number of filters - 1 (1 filter = 0)
          # Result: 0xC0 (both sizes, 1 filter) - matches XZ Utils default behavior
          # NOTE: xz command includes size fields by default for seeking/validation
          header.write([0xC0].pack("C"))

          # Compressed size (VLI encoding)
          compressed_size = block[:actual_compressed_size]
          header.write(self.class.encode_vli(compressed_size))

          # Uncompressed size (VLI encoding)
          header.write(self.class.encode_vli(block[:uncompressed_size]))

          # Filter flags: LZMA2 (0x21)
          header.write([0x21].pack("C"))

          # Properties size (1 byte)
          header.write([0x01].pack("C"))

          # Properties byte: LZMA2 dictionary size encoding
          # For LZMA2, this encodes dictionary size, NOT lc/lp/pb!
          # lc/lp/pb are encoded in LZMA2 chunk properties byte when RESET_PROPS flag is set
          dict_size = @options[:dict_size] || (1 << 23) # 8MB default
          props = Omnizip::Algorithms::LZMA2Encoder.encode_dict_size(dict_size)
          header.write([props].pack("C"))

          # Get header data (fields only, no size byte yet)
          header_fields = header.string

          # According to XZ spec, Block Header Size is in multiples of 4 bytes
          # and includes: size_byte + header_fields + padding + CRC32
          # The CRC is calculated over: size_byte + header_fields + padding

          # Calculate total size needed (must be multiple of 4)
          # We need: 1 (size) + header_fields.length + padding + 4 (CRC) = multiple of 4
          # So: (1 + header_fields.length + padding + 4) % 4 == 0
          # Therefore: (5 + header_fields.length + padding) % 4 == 0
          # So padding = (4 - ((5 + header_fields.length) % 4)) % 4
          base_size = 1 + header_fields.bytesize + 4 # size_byte + fields + CRC
          padding_needed = (4 - (base_size % 4)) % 4

          # Build the data that will be CRC'd (size_byte + fields + padding)
          total_size_bytes = base_size + padding_needed
          size_byte = [(total_size_bytes / 4) - 1].pack("C")

          # Data for CRC: size_byte + header_fields + padding
          crc_data = size_byte + header_fields + ("\x00" * padding_needed)

          # Calculate CRC32 of this data
          crc = Zlib.crc32(crc_data)

          # Write header:
          # 1. Size field (1 byte)
          @output.write(size_byte)

          # 2. Header fields
          @output.write(header_fields)

          # 3. Padding
          @output.write("\x00" * padding_needed) if padding_needed.positive?

          # 4. CRC32 (4 bytes, little-endian)
          @output.write([crc].pack("V"))
        end

        # Write padding to 4-byte boundary
        def write_padding
          pos = @output.pos
          padding = (4 - (pos % 4)) % 4
          @output.write("\x00" * padding) if padding.positive?
        end

        # Write check (CRC64)
        #
        # @param data [String] Data to checksum
        def write_check(data)
          # CRC64 (8 bytes) of UNCOMPRESSED data
          crc = Omnizip::Checksums::Crc64.calculate(data)
          @output.write([crc].pack("Q<"))
        end

        # Write index
        def write_index
          # Build index in buffer
          index_buffer = StringIO.new

          # Index indicator (0x00)
          index_buffer.write([0x00].pack("C"))

          # Number of records (VLI)
          index_buffer.write(self.class.encode_vli(@blocks.size))

          # Records
          @blocks.each do |block|
            index_buffer.write(self.class.encode_vli(block[:unpadded_size]))
            index_buffer.write(self.class.encode_vli(block[:uncompressed_size]))
          end

          # Get index data
          index_data = index_buffer.string

          # Write to output
          @output.write(index_data)

          # Padding to 4-byte boundary (based on index size, not file position)
          padding_needed = (4 - (index_data.bytesize % 4)) % 4
          @output.write("\x00" * padding_needed) if padding_needed.positive?

          # CRC32 of index (MUST include padding per XZ spec)
          # CRITICAL FIX: CRC is calculated over index_data + padding, not just index_data
          padding_str = "\x00" * padding_needed
          crc = Zlib.crc32(index_data + padding_str)
          @output.write([crc].pack("V"))

          # Store backward size for footer
          # Backward size = (index_data + padding) in 4-byte units, NOT including CRC32
          @backward_size = (index_data.bytesize + padding_needed) / 4
        end

        # Write stream footer (12 bytes)
        def write_stream_footer
          # Stream flags (2 bytes)
          flags = [0x00, 0x04].pack("C*")

          # Backward size (4 bytes) - size of index in 4-byte units
          backward_size_bytes = [@backward_size].pack("V")

          # CRC32 of backward_size + flags (6 bytes total)
          crc_data = backward_size_bytes + flags
          crc = Zlib.crc32(crc_data)
          @output.write([crc].pack("V"))

          # Backward size (4 bytes)
          @output.write(backward_size_bytes)

          # Stream flags (2 bytes)
          @output.write(flags)

          # Footer magic (2 bytes)
          @output.write(FOOTER_MAGIC.pack("C*"))
        end
      end
    end
  end
end
