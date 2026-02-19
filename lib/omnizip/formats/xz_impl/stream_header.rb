# frozen_string_literal: true

require_relative "constants"
require "zlib"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream Header encoder
      # Based on XZ Utils stream_flags_encoder.c
      class StreamHeader
        include Omnizip::Formats::XzConst

        attr_reader :check_type

        def initialize(check_type: CHECK_CRC64)
          @check_type = check_type
        end

        # Encode stream header (12 bytes total)
        # Format:
        #   - Magic (6 bytes): FD 37 7A 58 5A 00
        #   - Stream Flags (2 bytes): version + check type
        #   - CRC32 (4 bytes): CRC32 of Stream Flags
        def encode
          output = String.new(encoding: Encoding::BINARY)

          # Write magic bytes
          output << MAGIC.pack("C*")

          # Write stream flags (2 bytes)
          flags = encode_stream_flags
          output << flags

          # Write CRC32 of stream flags
          crc = Zlib.crc32(flags)
          output << [crc].pack("V") # Little-endian uint32

          output
        end

        def encode_stream_flags
          # Stream Flags format:
          #   Byte 0: Reserved (must be 0x00)
          #   Byte 1: Check type
          flags = String.new(encoding: Encoding::BINARY)
          flags << "\x00" # Reserved byte
          flags << [@check_type].pack("C")
          flags
        end
      end
    end
  end
end
