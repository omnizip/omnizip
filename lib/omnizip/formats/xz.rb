# frozen_string_literal: true

require "stringio"
require_relative "../algorithm_registry"
require_relative "xz/stream_header"
require_relative "xz/stream_footer"
require_relative "xz/block_header"

module Omnizip
  module Formats
    # XZ compression format
    #
    # XZ is a container format that wraps LZMA2 compression with
    # additional features like integrity checks and indexing.
    #
    # Format structure:
    # - Stream header (12 bytes)
    # - Blocks:
    #   - Block header (variable)
    #   - Compressed data (LZMA2)
    #   - Block padding (to 4-byte boundary)
    #   - Check (CRC32/CRC64/etc, optional)
    # - Index (variable)
    # - Stream footer (12 bytes)
    module Xz
      # Check types
      CHECK_NONE = 0
      CHECK_CRC32 = 1
      CHECK_CRC64 = 4
      CHECK_SHA256 = 10

      class << self
        # Compress a file with XZ
        #
        # @param input_path [String] Input file path
        # @param output_path [String] Output XZ file path
        # @param options [Hash] Compression options
        # @option options [Integer] :compression_level Level (0-9)
        # @option options [Integer] :check_type Check type
        def compress(input_path, output_path, options = {})
          input_data = File.binread(input_path)

          File.open(output_path, "wb") do |output|
            compress_stream(StringIO.new(input_data), output, options)
          end
        end

        # Decompress an XZ file
        #
        # @param input_path [String] Input XZ file path
        # @param output_path [String] Output file path
        def decompress(input_path, output_path)
          File.open(input_path, "rb") do |input|
            File.open(output_path, "wb") do |output|
              decompress_stream(input, output)
            end
          end
        end

        # Compress data stream with XZ
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Compression options
        def compress_stream(input_io, output_io, options = {})
          input_data = input_io.read
          check_type = options[:check_type] || CHECK_CRC32
          level = options[:compression_level] || options[:level] || 6

          # Write stream header
          header = StreamHeader.new(check_type)
          output_io.write(header.encode)

          # Compress data with LZMA2
          lzma2 = AlgorithmRegistry.get(:lzma2).new
          compressed_io = StringIO.new
          compressed_io.set_encoding(Encoding::BINARY)

          lzma2.compress(
            StringIO.new(input_data),
            compressed_io,
            build_compression_options(level)
          )

          compressed_io.rewind
          compressed_data = compressed_io.read

          # Write block header
          block_header = BlockHeader.new(
            uncompressed_size: input_data.bytesize,
            filters: [{ id: BlockHeader::FILTER_LZMA2 }]
          )
          output_io.write(block_header.encode)

          # Write compressed data
          output_io.write(compressed_data)

          # Pad to 4-byte boundary
          padding = (4 - (compressed_data.bytesize % 4)) % 4
          output_io.write("\0" * padding) if padding.positive?

          # Write check
          write_check(output_io, input_data, check_type)

          # Write index (simplified - single block)
          write_index(output_io, input_data.bytesize, compressed_data.bytesize)

          # Write stream footer
          footer = StreamFooter.new(check_type, 2) # Index is 2 blocks
          output_io.write(footer.encode)
        end

        # Decompress XZ stream
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        def decompress_stream(input_io, output_io)
          # Read stream header
          header_data = input_io.read(StreamHeader::SIZE)
          StreamHeader.decode(header_data)

          # Read block header
          BlockHeader.decode(input_io)

          # Read compressed data
          # For simplicity, read until we hit index/footer
          # In a full implementation, we'd use block_header.compressed_size
          compressed_data = StringIO.new
          compressed_data.set_encoding(Encoding::BINARY)

          # Read data in chunks until we can't decompress anymore
          chunk_size = 4096
          buffer = +""

          loop do
            chunk = input_io.read(chunk_size)
            break if chunk.nil? || chunk.empty?

            buffer << chunk

            # Try to find the index marker (0x00 byte)
            # This is a simplified approach
            next unless buffer.include?("\0\0\0\0")

            # Found potential padding/index
            # Extract just the compressed data
            compressed_end = buffer.index("\0\0\0\0")
            compressed_data.write(buffer[0...compressed_end])
            break
          end

          compressed_data.rewind

          # Decompress with LZMA2
          lzma2 = AlgorithmRegistry.get(:lzma2).new
          decompressed_io = StringIO.new
          decompressed_io.set_encoding(Encoding::BINARY)

          lzma2.decompress(compressed_data, decompressed_io)

          # Write decompressed data
          decompressed_io.rewind
          output_io.write(decompressed_io.read)
        end

        # Register XZ format when loaded
        def register!
          require_relative "../format_registry"
          FormatRegistry.register(".xz", Omnizip::Formats::Xz)
        end

        private

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

        # Write integrity check
        #
        # @param output [IO] Output stream
        # @param data [String] Data to check
        # @param check_type [Integer] Check type
        def write_check(output, data, check_type)
          case check_type
          when CHECK_NONE
            # No check
          when CHECK_CRC32
            crc32 = Zlib.crc32(data)
            output.write([crc32].pack("V"))
          when CHECK_CRC64
            # Simplified CRC64 (would need proper implementation)
            crc64 = Zlib.crc32(data).to_i
            output.write([crc64, 0].pack("VV"))
          else
            raise Error, "Unsupported check type: #{check_type}"
          end
        end

        # Write index
        #
        # @param output [IO] Output stream
        # @param uncompressed_size [Integer] Original size
        # @param compressed_size [Integer] Compressed size
        def write_index(output, uncompressed_size, _compressed_size)
          # Simplified index: just marks end of blocks
          # Real implementation would include record offsets
          index = [
            0x00,                    # Index indicator
            0x01,                    # Number of records (1 block)
            uncompressed_size & 0xFF # Simplified unpadded size
          ].pack("C C C")

          # Pad to 4-byte boundary
          padding = (4 - (index.bytesize % 4)) % 4
          index << ("\0" * padding) if padding.positive?

          # Add CRC32 of index
          crc32 = Zlib.crc32(index)
          output.write(index)
          output.write([crc32].pack("V"))
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::Xz.register!
