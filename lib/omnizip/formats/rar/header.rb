# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Rar
      # RAR header parser
      # Parses RAR4 and RAR5 archive headers
      class Header
        include Constants

        attr_reader :version, :flags, :is_multi_volume, :is_solid,
                    :is_locked, :comment_present

        # Read and parse RAR header
        #
        # @param io [IO] Input stream
        # @return [Header] Parsed header
        # @raise [RuntimeError] if invalid header
        def self.read(io)
          new.tap { |h| h.parse(io) }
        end

        # Initialize header
        def initialize
          @version = nil
          @flags = 0
          @is_multi_volume = false
          @is_solid = false
          @is_locked = false
          @comment_present = false
        end

        # Parse header from IO
        #
        # @param io [IO] Input stream
        # @raise [RuntimeError] if invalid header
        def parse(io)
          signature = io.read(8)
          return unless signature

          sig_bytes = signature.bytes

          if sig_bytes[0..6] == RAR5_SIGNATURE
            @version = 5
            parse_rar5_header(io)
          elsif sig_bytes[0..6] == RAR4_SIGNATURE
            @version = 4
            parse_rar4_header(io)
          else
            raise "Invalid RAR signature: #{sig_bytes.inspect}"
          end
        end

        # Check if header is valid
        #
        # @return [Boolean] true if valid
        def valid?
          !@version.nil?
        end

        # Check if RAR5 format
        #
        # @return [Boolean] true if RAR5
        def rar5?
          @version == 5
        end

        # Check if RAR4 format
        #
        # @return [Boolean] true if RAR4
        def rar4?
          @version == 4
        end

        private

        # Parse RAR4 header
        #
        # @param io [IO] Input stream
        def parse_rar4_header(io)
          # Read marker block
          read_uint16(io)
          head_type = io.read(1)&.ord
          read_uint16(io)
          read_uint16(io)

          unless head_type == BLOCK_MARKER
            raise "Expected marker block, got 0x#{head_type.to_s(16)}"
          end

          # Read archive header
          read_uint16(io)
          head_type = io.read(1)&.ord
          head_flags = read_uint16(io)
          head_size = read_uint16(io)

          unless head_type == BLOCK_ARCHIVE
            raise "Expected archive block, got 0x#{head_type.to_s(16)}"
          end

          @flags = head_flags
          @is_multi_volume = head_flags.anybits?(ARCHIVE_VOLUME)
          @is_solid = head_flags.anybits?(ARCHIVE_SOLID)
          @is_locked = head_flags.anybits?(ARCHIVE_LOCKED)
          @comment_present = head_flags.anybits?(ARCHIVE_COMMENT)

          # Skip rest of archive header
          remaining = head_size - 7
          io.read(remaining) if remaining.positive?
        end

        # Parse RAR5 header
        #
        # @param io [IO] Input stream
        def parse_rar5_header(io)
          # RAR5 uses variable-length integer encoding
          read_uint32(io)
          read_vint(io)
          header_type = read_vint(io)
          header_flags = read_vint(io)

          unless header_type == RAR5_HEADER_MAIN
            raise "Expected main header, got #{header_type}"
          end

          @flags = header_flags
          @is_multi_volume = header_flags.anybits?(RAR5_FLAG_MULTI_VOLUME)

          # Read extra area if present
          return unless header_flags.anybits?(RAR5_FLAG_EXTRA_AREA)

          extra_size = read_vint(io)
          io.read(extra_size) if extra_size.positive?
        end

        # Read 16-bit unsigned integer (little-endian)
        #
        # @param io [IO] Input stream
        # @return [Integer] Value
        def read_uint16(io)
          bytes = io.read(2)
          return 0 unless bytes&.size == 2

          bytes.unpack1("v")
        end

        # Read 32-bit unsigned integer (little-endian)
        #
        # @param io [IO] Input stream
        # @return [Integer] Value
        def read_uint32(io)
          bytes = io.read(4)
          return 0 unless bytes&.size == 4

          bytes.unpack1("V")
        end

        # Read variable-length integer (RAR5)
        #
        # @param io [IO] Input stream
        # @return [Integer] Value
        def read_vint(io)
          result = 0
          shift = 0

          loop do
            byte = io.read(1)&.ord
            return result unless byte

            result |= (byte & 0x7F) << shift
            break if byte.nobits?(0x80)

            shift += 7
          end

          result
        end
      end
    end
  end
end
