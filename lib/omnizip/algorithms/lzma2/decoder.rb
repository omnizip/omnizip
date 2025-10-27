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

require_relative "constants"
require_relative "properties"
require_relative "../lzma/decoder"

module Omnizip
  module Algorithms
    class LZMA2
      # LZMA2 Decoder - decodes LZMA2-compressed data
      #
      # This class implements the LZMA2 decoding algorithm by:
      # 1. Reading the property byte
      # 2. Processing chunks based on control bytes
      # 3. Decompressing LZMA chunks or copying uncompressed chunks
      # 4. Reassembling the original data
      #
      # The decoder reads a stream with:
      # - Property byte (dictionary size encoding)
      # - Sequence of chunks with control bytes
      # - End marker (0x00)
      class Decoder
        include Constants

        attr_reader :dict_size

        # Initialize the decoder
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options (reserved for future use)
        def initialize(input, options = {})
          @input = input
          @options = options

          read_property_byte
        end

        # Decode a compressed stream
        #
        # @return [String] Decompressed data
        def decode_stream
          output = []

          loop do
            control = read_control_byte
            break if control == CONTROL_END

            chunk_data = decode_chunk(control)
            output << chunk_data
          end

          output.join.force_encoding("ASCII-8BIT")
        end

        private

        # Read and parse LZMA2 property byte
        #
        # @return [void]
        # @raise [RuntimeError] If property byte is invalid
        def read_property_byte
          prop_byte = @input.getbyte
          raise "Invalid LZMA2 header" if prop_byte.nil?

          @properties = Properties.from_byte(prop_byte)
          @dict_size = @properties.actual_dict_size
        end

        # Read control byte
        #
        # @return [Integer] Control byte value
        # @raise [RuntimeError] If stream ends unexpectedly
        def read_control_byte
          byte = @input.getbyte
          raise "Unexpected end of stream" if byte.nil?

          byte
        end

        # Decode chunk based on control byte
        #
        # @param control [Integer] Control byte
        # @return [String] Decoded chunk data
        def decode_chunk(control)
          if uncompressed_chunk?(control)
            decode_uncompressed_chunk(control)
          else
            decode_compressed_chunk(control)
          end
        end

        # Check if control byte indicates uncompressed chunk
        #
        # @param control [Integer] Control byte
        # @return [Boolean] True if uncompressed
        def uncompressed_chunk?(control)
          [CONTROL_UNCOMPRESSED_RESET,
           CONTROL_UNCOMPRESSED_NO_RESET].include?(control)
        end

        # Decode uncompressed chunk
        #
        # @param control [Integer] Control byte
        # @return [String] Uncompressed data
        def decode_uncompressed_chunk(_control)
          # Read uncompressed size (2 bytes, big-endian)
          size = read_size_bytes(2) + 1

          # Read uncompressed data
          data = @input.read(size)
          raise "Unexpected end of stream" if data.nil? || data.bytesize != size

          data
        end

        # Decode compressed chunk
        #
        # @param control [Integer] Control byte
        # @return [String] Decompressed data
        def decode_compressed_chunk(_control)
          # Read uncompressed size (2 bytes, big-endian)
          uncompressed_size = read_size_bytes(2) + 1

          # Read compressed size (2 bytes, big-endian)
          compressed_size = read_size_bytes(2) + 1

          # Read compressed data
          compressed_data = @input.read(compressed_size)
          if compressed_data.nil? || compressed_data.bytesize != compressed_size
            raise "Unexpected end of stream"
          end

          # Decompress using LZMA
          decompress_lzma_chunk(compressed_data, uncompressed_size)
        end

        # Decompress LZMA chunk
        #
        # @param compressed_data [String] Compressed data (no LZMA header)
        # @param expected_size [Integer] Expected decompressed size
        # @return [String] Decompressed data
        def decompress_lzma_chunk(compressed_data, expected_size)
          # Reconstruct LZMA header since encoder stripped it
          header = build_lzma_header(expected_size)
          full_stream = header + compressed_data

          input_buffer = StringIO.new(full_stream)
          input_buffer.set_encoding("ASCII-8BIT")

          decoder = LZMA::Decoder.new(input_buffer)
          decompressed = decoder.decode_stream

          # Verify size matches expected
          if decompressed.bytesize != expected_size
            raise "Decompressed size mismatch: expected #{expected_size}, " \
                  "got #{decompressed.bytesize}"
          end

          decompressed
        end

        # Build LZMA header for decompression
        #
        # @param uncompressed_size [Integer] Expected size after decompression
        # @return [String] LZMA header (13 bytes)
        def build_lzma_header(uncompressed_size)
          header = String.new(encoding: "ASCII-8BIT")

          # Property byte (lc=3, lp=0, pb=2)
          props = 3 + (0 * 9) + (2 * 45)
          header << [props].pack("C")

          # Dictionary size (4 bytes, little-endian)
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
            raise "Unexpected end of stream" if byte.nil?

            size = (size << 8) | byte
          end
          size
        end
      end
    end
  end
end
