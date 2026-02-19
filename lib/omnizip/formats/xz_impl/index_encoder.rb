# frozen_string_literal: true

require "stringio"
require_relative "constants"
require "zlib"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Index encoder
      # Stores positions and sizes of all blocks in the stream
      class IndexEncoder
        include Omnizip::Formats::XzConst

        def initialize
          @records = []
        end

        # Add a block record to the index
        # @param unpadded_size [Integer] Block size without padding
        # @param uncompressed_size [Integer] Uncompressed size of the block
        def add_record(unpadded_size, uncompressed_size)
          @records << {
            unpadded: unpadded_size,
            uncompressed: uncompressed_size,
          }
        end

        # Encode the complete index
        # Returns the encoded index as a binary string
        def encode
          output = StringIO.new
          output.set_encoding(Encoding::BINARY)

          # Index Indicator (0x00)
          output.write("\x00")

          # Number of Records
          output.write(encode_vli(@records.size))

          # Encode each record
          @records.each do |record|
            # Unpadded Size
            output.write(encode_vli(record[:unpadded]))

            # Uncompressed Size
            output.write(encode_vli(record[:uncompressed]))
          end

          # Add padding to make index multiple of 4 bytes (including CRC32)
          # CRITICAL: Capture index_data before writing padding (StringIO#string returns a reference!)
          index_data = output.string.dup # Make a copy to avoid reference
          padding = calculate_padding(index_data.bytesize) # Pad to multiple of 4
          output.write("\x00" * padding) if padding.positive?

          # Calculate and write CRC32
          crc = Zlib.crc32(index_data + ("\x00" * padding))
          output.write([crc].pack("V"))

          output.string
        end

        # Get the size of the encoded index (for backward size)
        def size
          # Calculate without actually encoding
          size = 1 # Index Indicator
          size += vli_size(@records.size)

          @records.each do |record|
            size += vli_size(record[:unpadded])
            size += vli_size(record[:uncompressed])
          end

          # Add CRC32
          size += 4

          # Round up to multiple of 4
          ((size + 3) / 4) * 4
        end

        private

        def encode_vli(value)
          # Variable Length Integer encoding (1-9 bytes)
          output = String.new(encoding: Encoding::BINARY)

          loop do
            byte = value & 0x7F
            value >>= 7

            if value.zero?
              output << [byte].pack("C")
              break
            else
              output << [byte | 0x80].pack("C")
            end
          end

          output
        end

        def vli_size(value)
          # Calculate size of VLI-encoded value
          size = 0
          loop do
            size += 1
            value >>= 7
            break if value.zero?
          end
          size
        end

        def calculate_padding(size)
          # Pad to 4-byte boundary
          remainder = size % 4
          remainder.zero? ? 0 : 4 - remainder
        end
      end
    end
  end
end
