# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # RAR header parser
      # Parses RAR4 and RAR5 archive headers
      class Header
        include Omnizip::Formats::Rar::Constants

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
          # RAR4 signature is 7 bytes, RAR5 is 8 bytes
          # Read 7 bytes first to check for RAR4
          signature = io.read(7)
          return unless signature

          sig_bytes = signature.bytes

          if sig_bytes == RAR4_SIGNATURE
            @version = 4
            parse_rar4_header(io)
          elsif sig_bytes == RAR5_SIGNATURE[0..6]
            # Might be RAR5, read one more byte
            extra_byte = io.read(1)
            if extra_byte && (sig_bytes + extra_byte.bytes) == RAR5_SIGNATURE
              @version = 5
              parse_rar5_header(io)
            else
              raise "Invalid RAR signature: #{(sig_bytes + (extra_byte&.bytes || [])).inspect}"
            end
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
        # The 7-byte signature consumed by #parse IS the marker
        # block, so the main header follows immediately.
        #
        # @param io [IO] Input stream
        def parse_rar4_header(io)
          read_uint16(io) # HEAD_CRC
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

          # Skip rest of archive header. HEAD_SIZE counts the whole
          # block including the 2 HEAD_CRC bytes; 7 bytes consumed.
          remaining = head_size - 7
          io.read(remaining) if remaining.positive?
        end

        # Parse RAR5 header
        #
        # @param io [IO] Input stream
        def parse_rar5_header(io)
          # RAR5 uses variable-length integer encoding. Layout per the
          # RAR 5.0 format: HeaderCRC32(4), Header size(vint), Header
          # type(vint), Header flags(vint), then type-specific fields.
          read_uint32(io)
          read_vint(io) # header size (redundant: areas carry their own)
          header_type = read_vint(io)
          header_flags = read_vint(io)

          unless header_type == RAR5_HEADER_MAIN
            raise "Expected main header, got #{header_type}"
          end

          @flags = header_flags

          extra_size = 0
          if header_flags.anybits?(RAR5_FLAG_EXTRA_AREA)
            extra_size = read_vint(io)
          end

          # Archive flags: 0x0001 volume, 0x0002 volume number
          # present, 0x0004 solid, 0x0008 recovery, 0x0010 locked
          archive_flags = read_vint(io)
          @is_multi_volume = archive_flags.anybits?(0x0001)
          @is_solid = archive_flags.anybits?(0x0004)
          @is_locked = archive_flags.anybits?(0x0010)
          read_vint(io) if archive_flags.anybits?(0x0002) # volume number

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
