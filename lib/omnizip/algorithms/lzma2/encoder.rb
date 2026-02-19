# frozen_string_literal: true

require_relative "constants"
require_relative "properties"
require_relative "simple_lzma2_encoder"

module Omnizip
  module Algorithms
    # LZMA2 encoder - delegates to XzLZMA2Encoder
    #
    # This class provides a backward-compatible API that delegates to the
    # complete XzLZMA2Encoder implementation ported from XZ Utils.
    #
    # Based on XZ Utils lzma2_encoder.c
    class LZMA2Encoder
      attr_reader :dict_size, :lc, :lp, :pb

      # Initialize the encoder
      #
      # @param dict_size [Integer] Dictionary size (default: 8MB)
      # @param lc [Integer] Literal context bits (default: 3)
      # @param lp [Integer] Literal position bits (default: 0)
      # @param pb [Integer] Position bits (default: 2)
      # @param standalone [Boolean] If true, write property byte for
      #   standalone LZMA2 files (default: false)
      def initialize(
        dict_size: 8 * 1024 * 1024,
        lc: 3,
        lp: 0,
        pb: 2,
        standalone: false,
        **
      )
        @dict_size = dict_size
        @lc = lc
        @lp = lp
        @pb = pb
        @standalone = standalone

        # Create the SimpleLZMA2Encoder (uses working XzEncoder internally)
        @encoder = LZMA2::SimpleLZMA2Encoder.new(
          dict_size: dict_size,
          lc: lc,
          lp: lp,
          pb: pb,
          standalone: standalone,
        )
      end

      # Encode data into LZMA2 format
      #
      # @param input [String] Input data to compress
      # @return [String] LZMA2 compressed data
      def encode(input)
        @encoder.encode(input)
      end

      # Compress data from input stream to output stream
      # This method provides compatibility with the AlgorithmRegistry interface
      #
      # @param input_io [IO] Input stream to read from
      # @param output_io [IO] Output stream to write to
      # @param level [Integer] Compression level (not used, kept for compatibility)
      # @return [Integer] Number of bytes written
      def compress(input_io, output_io, _level = nil)
        input_data = input_io.read
        compressed = encode(input_data)
        output_io.write(compressed)
        compressed.bytesize
      end

      # Decompress data from input stream to output stream
      # This method provides compatibility with the AlgorithmRegistry interface
      #
      # @param input_io [IO] Input stream to read from
      # @param output_io [IO] Output stream to write to
      # @param size [Integer] Expected uncompressed size (optional)
      # @return [Integer] Number of bytes written
      def decompress(input_io, output_io, _size = nil)
        # Check if this is being called for 7-Zip format (raw LZMA2 stream)
        # 7-Zip stores LZMA2 without a property byte
        # We can detect this by checking if input_io is a StringIO (which is used
        # by StreamDecompressor for 7-Zip format)
        raw_mode = input_io.is_a?(StringIO)

        # Create a decoder instance
        decoder = LZMA2::Decoder.new(input_io, raw_mode: raw_mode)

        # For raw_mode (7-Zip format), we need to provide dict_size
        # Use default 8MB if not specified
        if raw_mode
          # Re-create decoder with dict_size option
          decoder = LZMA2::Decoder.new(input_io,
                                       raw_mode: true,
                                       dict_size: @dict_size)
        end

        # Decode the stream
        result = decoder.decode_stream

        # Write to output
        output_io.write(result)

        result.bytesize
      end

      # Encode dictionary size for LZMA2 properties
      # Returns a single byte encoding the dictionary size
      #
      # @param dict_size [Integer] Dictionary size to encode
      # @return [Integer] Encoded dictionary size byte
      def self.encode_dict_size(dict_size)
        # LZMA2 dictionary size encoding (XZ Utils format)
        # Byte value d encodes dictionary size as:
        #   If d < 40: size = 2^((d/2) + 12)  (for even d)
        #           or size = 3 * 2^((d-1)/2 + 11)  (for odd d)
        #   If d == 40: size = 0xFFFFFFFF (4GB - 1)

        # Clamp to valid range
        d = [dict_size, LZMA2Constants::DICT_SIZE_MIN].max

        # For 8MB (8 * 1024 * 1024 = 8388608 = 2^23):
        # We want: 2^((d/2) + 12) = 2^23
        # So: (d/2) + 12 = 23
        # Therefore: d/2 = 11, d = 22

        # Calculate log2 of dict_size
        log2_size = 0
        temp = d
        while temp > 1
          log2_size += 1
          temp >>= 1
        end

        # Encoding formula for power-of-2 sizes:
        # d = 2 * (log2_size - 12)
        if d == (1 << log2_size)
          # Exact power of 2
          [(log2_size - 12) * 2, 40].min
        else
          # Between 2^n and 2^n + 2^(n-1), use odd encoding
          [((log2_size - 12) * 2) + 1, 40].min
        end
      end
    end
  end
end
