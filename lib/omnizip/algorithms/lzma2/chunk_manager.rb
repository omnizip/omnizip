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

module Omnizip
  module Algorithms
    class LZMA2
      # LZMA2 Chunk Manager - handles chunk boundaries and decisions
      #
      # This class is responsible for:
      # - Splitting data into chunks of appropriate size
      # - Deciding whether to compress or store each chunk uncompressed
      # - Managing chunk buffering
      # - Providing thread safety infrastructure (for future use)
      #
      # The chunk manager implements intelligent compression decisions
      # based on compression ratio thresholds.
      #
      # IMPORTANT: LZMA2 format limits uncompressed chunk size to 65536 bytes
      # due to 2-byte size encoding. This manager enforces that limit.
      class ChunkManager
        include Constants

        attr_reader :chunk_size

        # Maximum bytes per chunk (LZMA2 spec limit)
        MAX_CHUNK_BYTES = UNCOMPRESSED_SIZE_MAX + 1 # 65536 bytes

        # Chunk data model
        #
        # Represents a single chunk of data with its metadata
        class Chunk
          attr_reader :data, :compressed_data, :is_compressed

          # Initialize a chunk
          #
          # @param data [String] Uncompressed chunk data
          def initialize(data)
            @data = data
            @compressed_data = nil
            @is_compressed = false
          end

          # Set compressed data
          #
          # @param compressed [String] Compressed data
          # @return [void]
          def compressed_data=(compressed)
            @compressed_data = compressed
            @is_compressed = true
          end

          # Get the data to write (compressed or uncompressed)
          #
          # @return [String] Data to write
          def output_data
            @is_compressed ? @compressed_data : @data
          end

          # Get size of output data
          #
          # @return [Integer] Size in bytes
          def output_size
            output_data.bytesize
          end

          # Get uncompressed size
          #
          # @return [Integer] Size in bytes
          def uncompressed_size
            @data.bytesize
          end
        end

        # Initialize chunk manager
        #
        # @param chunk_size [Integer] Desired chunk size
        def initialize(chunk_size = CHUNK_SIZE_DEFAULT)
          @chunk_size = validate_chunk_size(chunk_size)
          # Enforce LZMA2 format limit
          @effective_chunk_size = [@chunk_size, MAX_CHUNK_BYTES].min
        end

        # Split data into chunks
        #
        # @param data [String] Data to split
        # @return [Array<Chunk>] Array of chunks
        def create_chunks(data)
          chunks = []
          pos = 0

          while pos < data.bytesize
            chunk_data = data.byteslice(pos, @effective_chunk_size)
            chunks << Chunk.new(chunk_data)
            pos += @effective_chunk_size
          end

          chunks
        end

        # Decide if chunk should be compressed
        #
        # Makes decision based on compression ratio threshold.
        # If compressed size is not significantly smaller than
        # uncompressed size, store uncompressed.
        #
        # @param chunk [Chunk] Chunk with compressed data set
        # @return [Boolean] True if should use compression
        def should_compress?(chunk)
          return false unless chunk.compressed_data

          # Calculate compression ratio
          ratio = chunk.output_size.to_f / chunk.uncompressed_size

          # Only use compression if ratio is below threshold
          ratio < COMPRESSION_THRESHOLD
        end

        # Decide if chunk is last chunk
        #
        # @param chunk_index [Integer] Current chunk index
        # @param total_chunks [Integer] Total number of chunks
        # @return [Boolean] True if last chunk
        def last_chunk?(chunk_index, total_chunks)
          chunk_index == total_chunks - 1
        end

        # Calculate optimal chunk size for data
        #
        # This method can be used to dynamically adjust chunk size
        # based on data characteristics (future enhancement).
        #
        # @param data_size [Integer] Total data size
        # @return [Integer] Optimal chunk size
        def optimal_chunk_size(data_size)
          # For now, use effective chunk size
          # Future: could adjust based on data size
          return @effective_chunk_size if data_size <= @effective_chunk_size * 2

          # For larger data, might want larger chunks (up to max)
          [@effective_chunk_size * 2, MAX_CHUNK_BYTES].min
        end

        private

        # Validate chunk size
        #
        # @param size [Integer] Chunk size to validate
        # @return [Integer] Validated size
        # @raise [ArgumentError] If size is invalid
        def validate_chunk_size(size)
          unless size.between?(CHUNK_SIZE_MIN, CHUNK_SIZE_MAX)
            raise ArgumentError,
                  "Chunk size must be between #{CHUNK_SIZE_MIN} " \
                  "and #{CHUNK_SIZE_MAX}"
          end
          size
        end
      end
    end
  end
end
