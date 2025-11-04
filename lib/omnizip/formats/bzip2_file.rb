# frozen_string_literal: true

require "stringio"
require_relative "../algorithm_registry"

module Omnizip
  module Formats
    # BZIP2 file format
    #
    # BZIP2 is a file compression format that uses the BZip2 algorithm
    # with block-sorting compression (Burrows-Wheeler Transform).
    #
    # Format structure:
    # - Magic bytes: "BZh" (0x42 0x5A 0x68)
    # - Block size indicator: '1'-'9' (100KB - 900KB)
    # - Compressed blocks
    # - End-of-stream marker
    #
    # The format supports multiple compressed blocks, each with its own
    # CRC32 checksum for data integrity verification.
    module Bzip2File
      # BZIP2 magic bytes
      BZIP2_MAGIC = "BZh"

      # Block size markers ('1' to '9')
      BLOCK_SIZE_MIN = 1
      BLOCK_SIZE_MAX = 9

      # Stream markers
      STREAM_MAGIC = 0x314159265359 # π in hex
      BLOCK_MAGIC = 0x177245385090  # Block start marker
      STREAM_END_MAGIC = 0x177245385090 # Stream end marker

      class << self
        # Compress a file with BZIP2
        #
        # @param input_path [String] Input file path
        # @param output_path [String] Output BZIP2 file path
        # @param options [Hash] Compression options
        # @option options [Integer] :level Compression level (1-9)
        def compress(input_path, output_path, options = {})
          input_data = File.binread(input_path)

          File.open(output_path, "wb") do |output|
            compress_stream(StringIO.new(input_data), output, options)
          end
        end

        # Decompress a BZIP2 file
        #
        # @param input_path [String] Input BZIP2 file path
        # @param output_path [String] Output file path
        def decompress(input_path, output_path)
          File.open(input_path, "rb") do |input|
            File.open(output_path, "wb") do |output|
              decompress_stream(input, output)
            end
          end
        end

        # Compress data stream with BZIP2
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Compression options
        def compress_stream(input_io, output_io, options = {})
          level = options[:level] || 9
          level = level.clamp(BLOCK_SIZE_MIN, BLOCK_SIZE_MAX)

          input_data = input_io.read

          # Write BZIP2 header
          write_header(output_io, level)

          # Get BZip2 algorithm
          bzip2 = AlgorithmRegistry.get(:bzip2).new

          # Compress data
          compressed_io = StringIO.new
          compressed_io.set_encoding(Encoding::BINARY)

          bzip2.compress(
            StringIO.new(input_data),
            compressed_io,
            build_compression_options(level)
          )

          # Write compressed data
          compressed_io.rewind
          compressed_data = compressed_io.read
          output_io.write(compressed_data)
        end

        # Decompress BZIP2 stream
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        def decompress_stream(input_io, output_io)
          # Read and verify header
          read_header(input_io)

          # Get BZip2 algorithm
          bzip2 = AlgorithmRegistry.get(:bzip2).new

          # Decompress data
          decompressed_io = StringIO.new
          decompressed_io.set_encoding(Encoding::BINARY)

          bzip2.decompress(input_io, decompressed_io)

          # Write decompressed data
          decompressed_io.rewind
          output_io.write(decompressed_io.read)
        end

        # Register BZIP2 format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".bz2", Omnizip::Formats::Bzip2File)
          FormatRegistry.register(".bzip2", Omnizip::Formats::Bzip2File)
        end

        private

        # Write BZIP2 header
        #
        # @param output [IO] Output stream
        # @param level [Integer] Compression level (1-9)
        def write_header(output, level)
          # BZIP2 magic: "BZh" + block size
          header = "#{BZIP2_MAGIC}#{level}"
          output.write(header)
        end

        # Read BZIP2 header
        #
        # @param input [IO] Input stream
        # @return [Integer] Block size level
        def read_header(input)
          magic = input.read(3)
          unless magic == BZIP2_MAGIC
            raise Error, "Not a BZIP2 file (invalid magic bytes)"
          end

          level_char = input.read(1)
          level = level_char.to_i

          unless level.between?(BLOCK_SIZE_MIN, BLOCK_SIZE_MAX)
            raise Error, "Invalid BZIP2 block size: #{level_char}"
          end

          level
        end

        # Build compression options
        #
        # @param level [Integer] Compression level
        # @return [Object] Compression options
        def build_compression_options(level)
          require_relative "../models/compression_options"

          Models::CompressionOptions.new.tap do |opts|
            opts.level = level
          end
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Bzip2File.register!
