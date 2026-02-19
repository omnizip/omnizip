# frozen_string_literal: true

require_relative "constants"
require_relative "../../algorithms/lzma2"
require_relative "../../checksums/crc32"

module Omnizip
  module Formats
    module SevenZip
      # Handles 7-Zip encoded headers
      #
      # 7-Zip can compress the Next Header metadata with LZMA2 to save space.
      # This module provides functionality to encode and decode headers.
      module EncodedHeader
        include Constants

        module_function

        # Encode next header with LZMA2 compression
        #
        # @param header_data [String] Uncompressed header data
        # @return [String] Encoded header property with compressed data
        def encode(header_data)
          # Compress header with LZMA2
          compressed = compress_header(header_data)

          # Build encoded header property
          encoded = String.new(encoding: "BINARY")
          encoded << [PropertyId::ENCODED_HEADER].pack("C")

          # Write pack info for compressed header
          encoded << [PropertyId::PACK_INFO].pack("C")
          encoded << encode_uint64(0)  # Pack position
          encoded << encode_uint64(1)  # Number of pack streams

          # Write size
          encoded << [PropertyId::SIZE].pack("C")
          encoded << encode_uint64(compressed.bytesize)

          encoded << [PropertyId::K_END].pack("C")

          # Write coder info (LZMA2)
          encoded << [PropertyId::UNPACK_INFO].pack("C")
          encoded << [PropertyId::FOLDER].pack("C")
          encoded << encode_uint64(1)  # Number of folders
          encoded << [0].pack("C")     # External flag (0 = inline)

          # Number of coders
          encoded << encode_uint64(1)

          # Coder info for LZMA2
          # Method ID: LZMA2 = 0x21
          encoded << [1].pack("C") # Main byte (1 byte for ID, no properties)
          encoded << [0x21].pack("C") # LZMA2 method ID

          # Unpack size
          encoded << [PropertyId::CODERS_UNPACK_SIZE].pack("C")
          encoded << encode_uint64(header_data.bytesize)

          encoded << [PropertyId::K_END].pack("C")

          # Append compressed data
          encoded << compressed

          encoded
        end

        # Compress header data with LZMA2
        #
        # @param header_data [String] Uncompressed header
        # @return [String] Compressed header
        def compress_header(header_data)
          # Use 7-Zip SDK LZMA2 encoder for 7-Zip format
          encoder = Omnizip::Implementations::SevenZip::LZMA2::Encoder.new(
            dict_size: 4096, # Small dictionary for headers
            lc: 3,
            lp: 0,
            pb: 2,
            standalone: false, # No property byte
          )

          encoder.encode(header_data)
        end

        # Encode unsigned 64-bit integer in 7-Zip variable-length format
        #
        # @param value [Integer] Value to encode
        # @return [String] Encoded bytes
        def encode_uint64(value)
          return [value].pack("C") if value < 0x80

          result = String.new(encoding: "BINARY")
          shift = 0

          loop do
            byte = value & 0x7F
            value >>= 7

            if value.zero?
              result << [byte].pack("C")
              break
            else
              result << [byte | 0x80].pack("C")
            end

            shift += 7
          end

          result
        end
      end
    end
  end
end
