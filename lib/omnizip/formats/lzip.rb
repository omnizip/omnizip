# frozen_string_literal: true

require "stringio"

module Omnizip
  module Formats
    #
    # LZIP (.lz) compression format
    #
    # Lzip is a file compression format that uses LZMA compression with a
    # simple container format. It was created as an alternative to the
    # legacy .lzma format with better integrity checking.
    #
    # This is DIFFERENT from both XZ and .lzma (LZMA_Alone) formats:
    # - XZ (.xz): Container format with stream header/footer/index, LZMA2 compression
    # - LZIP (.lz): Standalone format with "LZIP" magic and CRC32 footer, LZMA1 compression
    # - LZMA_Alone (.lzma): Legacy standalone format with properties byte, LZMA1 compression
    #
    # Format structure:
    # - Header (6 bytes):
    #   - Magic bytes: "LZIP" (0x4C 0x5A 0x49 0x50)
    #   - Version (1 byte): 0 or 1
    #   - Dictionary size (1 byte): encoded format
    # - LZMA1 compressed stream (with fixed LC=3, LP=0, PB=2)
    # - Footer:
    #   - Version 0 (12 bytes): CRC32 (4) + Uncompressed size (8)
    #   - Version 1 (20 bytes): CRC32 (4) + Uncompressed size (8) + Member size (8)
    #
    # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/lzip_decoder.c
    #
    module Lzip
      # Lzip magic bytes: "LZIP" in ASCII
      # Reference: lzip_decoder.c:106
      MAGIC = [0x4C, 0x5A, 0x49, 0x50].pack("C*")

      # Fixed LC/LP/PB values for lzip format
      # Reference: lzip_decoder.c:23-26
      LZIP_LC = 3
      LZIP_LP = 0
      LZIP_PB = 2

      # Minimum and maximum dictionary sizes (in bytes)
      # Reference: lzip_decoder.c:197-198
      MIN_DICT_SIZE = 4096 # 4 KiB
      MAX_DICT_SIZE = (512 << 20) # 512 MiB

      class << self
        # Compress a file with LZIP
        #
        # @param input_path [String] Input file path
        # @param output_path [String] Output LZIP file path
        # @param options [Hash] Compression options
        # @option options [Integer] :level Compression level (0-9, default: 6)
        # @option options [Integer] :dict_size Dictionary size (default: auto from level)
        # @option options [Integer] :version LZIP version (0 or 1, default: 1)
        def compress(input_path, output_path, options = {})
          input_data = File.binread(input_path)

          File.open(output_path, "wb") do |output|
            compress_stream(
              StringIO.new(input_data),
              output,
              options,
            )
          end
        end

        # Decompress LZIP data
        #
        # @param input [String, IO] Input data, file path, or IO object
        # @param output [String, IO, nil] Output file path or IO object
        # @param options [Hash] Options
        # @option options [Boolean] :ignore_check If true, skip CRC32 verification (default: false)
        # @option options [Boolean] :concatenated If true, decode concatenated .lz members (default: false)
        # @return [String, nil] Decompressed data (if output is nil)
        def decompress(input, output = nil, options = {})
          data = Omnizip::IO::Source.for(input).read

          # Decode using LzipDecoder
          decoder = Omnizip::Algorithms::LZMA::LzipDecoder.new(
            StringIO.new(data),
            options,
          )
          result = decoder.decode_stream

          if output
            Omnizip::IO::Sink.for(output).write(result)
          else
            result
          end
        end

        # Decode LZIP data (alias for decompress with no output)
        #
        # @param input [String, IO] Input LZIP data or file path
        # @return [String] Decompressed data
        def decode(input)
          decompress(input)
        end

        # Compress data stream with LZIP
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Compression options
        def compress_stream(input_io, output_io, options = {})
          input = input_io.read

          # Version-1 member: magic + version + dict-size byte, LZMA1
          # body (EOPM-terminated), 20-byte trailer (CRC32 + data
          # size + member size). The dictionary byte uses lzip's
          # 5-bit exponent / 3-bit fraction encoding; 4 MiB is the
          # typical default.
          output_io.write(MAGIC)
          output_io.write([1].pack("C"))
          output_io.write([22].pack("C")) # 2^22 = 4 MiB, no fraction

          dict_size = options.fetch(:dict_size, 8 * 1024 * 1024)
          body = Algorithms::LZMA::Lzma1Encoder
            .new(dict_size: dict_size).encode(input)

          member_size = 6 + body.bytesize + 20
          output_io.write(body)
          output_io.write([Checksums::Crc32.calculate(input)].pack("V"))
          output_io.write([input.bytesize].pack("Q<"))
          output_io.write([member_size].pack("Q<"))
        end

        # Decompress LZIP stream
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Options
        # @return [Hash] Metadata (version, dict_size, member_size)
        def decompress_stream(input_io, output_io, options = {})
          output_io.set_encoding(Encoding::BINARY)
          decoder = Omnizip::Algorithms::LZMA::LzipDecoder.new(input_io,
                                                               options)
          result = decoder.decode_stream

          output_io.write(result)

          # Return metadata
          {
            version: decoder.version,
            dict_size: decoder.dict_size,
            member_size: decoder.member_size,
          }
        end

        # Detect if data is LZIP format
        #
        # @param data [String] Data to check
        # @return [Boolean] true if data has LZIP magic bytes
        def lzip_file?(data)
          data.start_with?(MAGIC)
        end
      end
    end
  end
end
