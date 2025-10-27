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
require_relative "chunk_manager"
require_relative "../lzma/encoder"

module Omnizip
  module Algorithms
    class LZMA2
      # LZMA2 Encoder - wraps LZMA encoder with chunking
      #
      # This class implements the LZMA2 encoding algorithm by:
      # 1. Splitting input into manageable chunks
      # 2. Compressing each chunk with LZMA
      # 3. Deciding whether to use compressed or uncompressed data
      # 4. Writing control bytes and chunk data
      #
      # The encoder produces a stream with:
      # - Property byte (dictionary size encoding)
      # - Sequence of chunks, each with:
      #   * Control byte
      #   * Uncompressed size (if needed)
      #   * Compressed size (if needed)
      #   * Chunk data
      # - End marker (0x00)
      class Encoder
        include Constants

        attr_reader :dict_size, :chunk_size

        # LZMA header size: 1 prop + 4 dict_size + 8 uncompressed_size
        LZMA_HEADER_SIZE = 13

        # Initialize the encoder
        #
        # @param output [IO] Output stream for compressed data
        # @param options [Hash] Encoding options
        # @option options [Integer] :dict_size Dictionary size
        # @option options [Integer] :chunk_size Chunk size
        def initialize(output, options = {})
          @output = output
          @dict_size = options[:dict_size] || (1 << 23)
          @chunk_size = options[:chunk_size] || CHUNK_SIZE_DEFAULT

          @properties = Properties.new(@dict_size)
          @chunk_manager = ChunkManager.new(@chunk_size)
        end

        # Encode a stream of data
        #
        # @param input [String, IO] Input data to compress
        # @return [void]
        def encode_stream(input)
          data = input.is_a?(String) ? input : input.read
          # Ensure binary encoding without modifying frozen string
          data = data.dup.force_encoding("ASCII-8BIT")

          # Write property byte
          write_property_byte

          # Create and encode chunks
          chunks = @chunk_manager.create_chunks(data)
          encode_chunks(chunks)

          # Write end marker
          write_end_marker
        end

        private

        # Write LZMA2 property byte
        #
        # @return [void]
        def write_property_byte
          @output.putc(@properties.prop_byte)
        end

        # Encode all chunks
        #
        # @param chunks [Array<ChunkManager::Chunk>] Chunks to encode
        # @return [void]
        def encode_chunks(chunks)
          chunks.each_with_index do |chunk, index|
            encode_chunk(chunk, index.zero?)
          end
        end

        # Encode a single chunk
        #
        # @param chunk [ChunkManager::Chunk] Chunk to encode
        # @param reset_dict [Boolean] Whether to reset dictionary
        # @return [void]
        def encode_chunk(chunk, reset_dict)
          # Try compressing the chunk
          compressed = compress_chunk_data(chunk.data)
          chunk.compressed_data = compressed

          # Decide whether to use compression
          if @chunk_manager.should_compress?(chunk)
            write_compressed_chunk(chunk, reset_dict)
          else
            write_uncompressed_chunk(chunk, reset_dict)
          end
        end

        # Compress chunk data using LZMA
        #
        # @param data [String] Data to compress
        # @return [String] Compressed data (without LZMA header)
        def compress_chunk_data(data)
          output_buffer = StringIO.new
          output_buffer.set_encoding("ASCII-8BIT")

          # Create LZMA encoder with current properties
          lzma_options = {
            dict_size: @properties.actual_dict_size,
            lc: 3,
            lp: 0,
            pb: 2
          }

          encoder = LZMA::Encoder.new(output_buffer, lzma_options)
          encoder.encode_stream(data)

          # Strip LZMA header (13 bytes) - LZMA2 manages headers differently
          full_output = output_buffer.string
          full_output.byteslice(LZMA_HEADER_SIZE..-1) || ""
        end

        # Write compressed chunk
        #
        # @param chunk [ChunkManager::Chunk] Chunk to write
        # @param reset_dict [Boolean] Whether to reset dictionary
        # @return [void]
        def write_compressed_chunk(chunk, reset_dict)
          control = build_compressed_control(reset_dict)
          @output.putc(control)

          # Write uncompressed size (2 bytes, big-endian)
          write_size_bytes(chunk.uncompressed_size - 1, 2)

          # Write compressed size (2 bytes, big-endian)
          # Subtract 1 as per LZMA2 spec
          write_size_bytes(chunk.output_size - 1, 2)

          # Write compressed data
          @output.write(chunk.output_data)
        end

        # Write uncompressed chunk
        #
        # @param chunk [ChunkManager::Chunk] Chunk to write
        # @param reset_dict [Boolean] Whether to reset dictionary
        # @return [void]
        def write_uncompressed_chunk(chunk, reset_dict)
          control = if reset_dict
                      CONTROL_UNCOMPRESSED_RESET
                    else
                      CONTROL_UNCOMPRESSED_NO_RESET
                    end
          @output.putc(control)

          # Write uncompressed size (2 bytes, big-endian)
          write_size_bytes(chunk.uncompressed_size - 1, 2)

          # Write uncompressed data
          @output.write(chunk.data)
        end

        # Build control byte for compressed chunk
        #
        # @param reset_dict [Boolean] Whether to reset dictionary
        # @return [Integer] Control byte value
        def build_compressed_control(_reset_dict)
          # For simplicity, always use LZMA with reset
          # Future: could optimize to reuse dictionary
          CONTROL_LZMA_RESET_NO_PROPS
        end

        # Write size as bytes
        #
        # @param size [Integer] Size value
        # @param num_bytes [Integer] Number of bytes to write
        # @return [void]
        def write_size_bytes(size, num_bytes)
          # Write in big-endian order
          (num_bytes - 1).downto(0) do |i|
            @output.putc((size >> (i * 8)) & 0xFF)
          end
        end

        # Write end marker
        #
        # @return [void]
        def write_end_marker
          @output.putc(CONTROL_END)
        end
      end
    end
  end
end
