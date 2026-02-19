# frozen_string_literal: true

require_relative "solid_stream"
require_relative "solid_encoder"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Solid
          # Solid compression manager
          #
          # This manager coordinates solid compression by:
          # 1. Collecting files into a SolidStream
          # 2. Compressing the entire stream with persistent dictionary
          # 3. Tracking file boundaries for extraction
          #
          # The result is better compression ratios at the cost of:
          # - Cannot extract individual files without decompressing entire solid block
          # - Corruption in one file may affect others in the same block
          #
          # @example Create solid archive
          #   manager = SolidManager.new(level: 5)
          #   manager.add_file('file1.txt', data1)
          #   manager.add_file('file2.txt', data2)
          #   compressed = manager.compress_all
          class SolidManager
            # @return [SolidStream] File stream
            attr_reader :stream

            # @return [SolidEncoder] Compression encoder
            attr_reader :encoder

            # @return [Integer] Compression level
            attr_reader :level

            # Initialize solid manager
            #
            # @param options [Hash] Options
            # @option options [Integer] :level Compression level (1-5, default: 3)
            def initialize(options = {})
              @level = options[:level] || 3
              @stream = SolidStream.new
              @encoder = SolidEncoder.new(level: @level)
            end

            # Add file to solid block
            #
            # @param filename [String] File name
            # @param data [String] File data
            # @param metadata [Hash] File metadata
            # @return [void]
            def add_file(filename, data, metadata = {})
              @stream.add_file(filename, data, metadata)
            end

            # Compress all files in solid mode
            #
            # Returns compressed data and file metadata needed for headers.
            #
            # @return [Hash] Compressed result
            # @option result [String] :compressed_data The compressed stream
            # @option result [Integer] :compressed_size Size of compressed data
            # @option result [Integer] :uncompressed_size Total uncompressed size
            # @option result [Array<Hash>] :files File metadata with offsets
            def compress_all
              # Get concatenated data
              data = @stream.concatenated_data

              # Compress entire stream
              compressed = @encoder.compress_stream(data)

              {
                compressed_data: compressed,
                compressed_size: compressed.bytesize,
                uncompressed_size: data.bytesize,
                files: @stream.files.dup,
              }
            end

            # Decompress solid stream and extract file
            #
            # @param compressed_data [String] Compressed data
            # @param file_index [Integer] File index to extract
            # @return [String, nil] File data or nil if not found
            def extract_file(compressed_data, file_index)
              # Validate index
              return nil if file_index.negative? || file_index >= @stream.file_count

              # Decompress entire stream
              decompressed = @encoder.decompress_stream(compressed_data)

              # Extract specific file
              file = @stream.file_at(file_index)
              return nil unless file

              decompressed[file[:offset], file[:size]]
            end

            # Get file count
            #
            # @return [Integer] Number of files
            def file_count
              @stream.file_count
            end

            # Get total uncompressed size
            #
            # @return [Integer] Total size in bytes
            def total_size
              @stream.total_size
            end

            # Check if manager has files
            #
            # @return [Boolean] true if files added
            def has_files?
              !@stream.empty?
            end

            # Clear all data
            #
            # @return [void]
            def clear
              @stream.clear
            end

            # Calculate compression ratio
            #
            # @param compressed_size [Integer] Compressed data size
            # @return [Float] Compression ratio (0.0-1.0)
            def compression_ratio(compressed_size)
              return 0.0 if total_size.zero?

              compressed_size.to_f / total_size
            end
          end
        end
      end
    end
  end
end
