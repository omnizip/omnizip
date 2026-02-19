# frozen_string_literal: true

require_relative "constants"
require "zlib"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream Footer encoder
      # Based on XZ Utils stream_flags_encoder.c
      class StreamFooter
        include Omnizip::Formats::XzConst

        attr_reader :check_type, :backward_size

        def initialize(backward_size:, check_type: CHECK_CRC64)
          @check_type = check_type
          @backward_size = backward_size
        end

        # Encode stream footer (12 bytes total)
        # Format:
        #   - CRC32 (4 bytes): CRC32 of backward size + stream flags
        #   - Backward Size (4 bytes): Size of Index in 4-byte multiples
        #   - Stream Flags (2 bytes): version + check type
        #   - Footer Magic (2 bytes): 59 5A
        def encode
          output = String.new(encoding: Encoding::BINARY)

          # Validate backward size
          unless valid_backward_size?
            raise ArgumentError, "Invalid backward size: #{@backward_size}"
          end

          # Encode backward size (stored as (bytes / 4) - 1)
          backward_encoded = (@backward_size / 4) - 1
          backward_bytes = [backward_encoded].pack("V") # Little-endian uint32

          # Encode stream flags
          flags = encode_stream_flags

          # Calculate CRC32 of backward size + flags
          crc_data = backward_bytes + flags
          crc = Zlib.crc32(crc_data)

          # Write CRC32
          output << [crc].pack("V")

          # Write backward size
          output << backward_bytes

          # Write stream flags
          output << flags

          # Write footer magic
          output << FOOTER_MAGIC.pack("C*")

          output
        end

        private

        def encode_stream_flags
          # Stream Flags format:
          #   Byte 0: Reserved (must be 0x00)
          #   Byte 1: Check type
          flags = String.new(encoding: Encoding::BINARY)
          flags << "\x00" # Reserved byte
          flags << [@check_type].pack("C")
          flags
        end

        def valid_backward_size?
          @backward_size.between?(BACKWARD_SIZE_MIN, BACKWARD_SIZE_MAX) &&
            (@backward_size % 4).zero?
        end
      end
    end
  end
end
