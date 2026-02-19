# frozen_string_literal: true

require "stringio"
require_relative "../algorithms/lzma"
require_relative "../format_registry"

module Omnizip
  module Formats
    #
    # LZMA_Alone (.lzma) compression format
    #
    # This is the legacy LZMA_Alone format used by LZMA Utils 4.32.x.
    # It is DIFFERENT from both XZ and LZIP formats:
    # - XZ (.xz): Container format with stream header/footer/index, LZMA2 compression
    # - LZIP (.lz): Standalone format with "LZIP" magic and CRC32 footer, LZMA1 compression
    # - LZMA_Alone (.lzma): Legacy standalone format with properties byte, LZMA1 compression
    #
    # Format structure:
    # - Properties (1 byte): encodes lc, lp, pb values
    # - Dictionary size (4 bytes, little-endian)
    # - Uncompressed size (8 bytes, little-endian, UINT64_MAX = unknown)
    # - LZMA1 compressed stream (no footer, no CRC32)
    #
    # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/alone_decoder.c
    #
    module LzmaAlone
      # Maximum valid uncompressed size (256 GiB)
      # From alone_decoder.c:118
      MAX_UNCOMPRESSED_SIZE = (1 << 38)

      # Property byte validation limits
      # From lzma_decoder.c:1218
      MAX_PROPERTY_BYTE = (((4 * 5) + 4) * 9) + 8 # = 233

      # Value indicating unknown uncompressed size
      UINT64_MAX = (1 << 64) - 1

      class << self
        # Compress a file with LZMA_Alone format
        #
        # @param input_path [String] Input file path
        # @param output_path [String] Output LZMA_Alone file path
        # @param options [Hash] Compression options
        # @option options [Integer] :lc Literal context bits (0-8, default: 3)
        # @option options [Integer] :lp Literal position bits (0-4, default: 0)
        # @option options [Integer] :pb Position bits (0-4, default: 2)
        # @option options [Integer] :dict_size Dictionary size (default: 8MB)
        # @option options [Integer] :uncompressed_size Explicit uncompressed size (default: unknown)
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

        # Decompress LZMA_Alone data
        #
        # @param input [String, IO] Input data, file path, or IO object
        # @param output [String, IO, nil] Output file path or IO object
        # @param options [Hash] Options
        # @option options [Boolean] :picky If true, reject files unlikely to be .lzma (default: false)
        # @return [String, nil] Decompressed data (if output is nil)
        def decompress(input, output = nil, options = {})
          # Handle raw data string vs file path
          data = if input.respond_to?(:read)
                   input.read
                 elsif input.is_a?(String)
                   if !input.include?("\0") && File.exist?(input)
                     File.binread(input)
                   else
                     input.b
                   end
                 else
                   raise ArgumentError,
                         "Input must be a String or IO object"
                 end

          # Decode using LzmaAloneDecoder
          require_relative "../algorithms/lzma/lzma_alone_decoder"
          decoder = Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(
            StringIO.new(data),
            options,
          )
          result = decoder.decode_stream

          if output
            if output.respond_to?(:write)
              output.write(result)
            else
              File.binwrite(output, result)
            end
          else
            result
          end
        end

        # Decode LZMA_Alone data (alias for decompress with no output)
        #
        # @param input [String, IO] Input LZMA_Alone data or file path
        # @return [String] Decompressed data
        def decode(input)
          decompress(input)
        end

        # Compress data stream with LZMA_Alone format
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Compression options
        def compress_stream(input_io, output_io, options = {})
          input_data = input_io.read

          # Get encoding parameters
          lc = options[:lc] || 3
          lp = options[:lp] || 0
          pb = options[:pb] || 2
          dict_size = options[:dict_size] || (8 * 1024 * 1024)
          uncompressed_size = options[:uncompressed_size] || input_data.bytesize

          # Encode properties byte
          prop_byte = (((pb * 5) + lp) * 9) + lc

          # Write header
          output_io.write([prop_byte].pack("C"))
          output_io.write([dict_size].pack("V"))
          output_io.write([uncompressed_size].pack("Q<"))

          # TODO: Implement LZMA1 encoder
          raise NotImplementedError,
                "LZMA_Alone encoding not yet implemented. Use decompression only."
        end

        # Decompress LZMA_Alone stream
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Options
        # @return [Hash] Metadata (lc, lp, pb, dict_size, uncompressed_size)
        def decompress_stream(input_io, output_io, options = {})
          require_relative "../algorithms/lzma/lzma_alone_decoder"
          decoder = Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(input_io, options)
          result = decoder.decode_stream

          output_io.write(result)

          # Return metadata
          {
            lc: decoder.instance_variable_get(:@lc),
            lp: decoder.instance_variable_get(:@lp),
            pb: decoder.instance_variable_get(:@pb),
            dict_size: decoder.instance_variable_get(:@dict_size),
            uncompressed_size: decoder.instance_variable_get(:@uncompressed_size),
          }
        end

        # Register LZMA_Alone format when loaded
        def register!
          FormatRegistry.register(".lzma", Omnizip::Formats::LzmaAlone)
        end
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::LzmaAlone.register!
