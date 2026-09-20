# frozen_string_literal: true

require "zlib"
require "stringio"

module Omnizip
  module Formats
    # GZIP compression format
    #
    # GZIP is a file compression format that wraps Deflate compression
    # with a 10-byte header and 8-byte footer containing CRC32 and
    # uncompressed size.
    #
    # Format structure:
    # - Header (10 bytes minimum):
    #   - Magic bytes: 0x1F 0x8B
    #   - Compression method: 0x08 (Deflate)
    #   - Flags
    #   - Modification time (4 bytes)
    #   - Extra flags
    #   - OS type
    # - Compressed data (Deflate)
    # - Footer (8 bytes):
    #   - CRC32 (4 bytes)
    #   - Uncompressed size (4 bytes, modulo 2^32)
    module Gzip
      # GZIP magic bytes
      GZIP_MAGIC = [0x1F, 0x8B].pack("C*")

      # Compression method (Deflate)
      CM_DEFLATE = 8

      # Flag bits
      FTEXT = 0x01      # File is text
      FHCRC = 0x02      # Header CRC present
      FEXTRA = 0x04     # Extra fields present
      FNAME = 0x08      # Original filename present
      FCOMMENT = 0x10   # Comment present

      # OS types
      OS_FAT = 0        # FAT filesystem
      OS_UNIX = 3       # Unix
      OS_UNKNOWN = 255  # Unknown

      class << self
        # Compress a file with GZIP
        #
        # @param input_path [String] Input file path
        # @param output_path [String] Output GZIP file path
        # @param options [Hash] Compression options
        # @option options [Integer] :level Compression level (0-9)
        # @option options [String] :original_name Original filename
        # @option options [Time] :mtime Modification time
        def compress(input_path, output_path, options = {})
          input_data = File.binread(input_path)

          File.open(output_path, "wb") do |output|
            original_name = options[:original_name] ||
              File.basename(input_path)
            compress_stream(
              StringIO.new(input_data),
              output,
              options.merge(original_name: original_name),
            )
          end
        end

        # Decompress a GZIP file
        #
        # @param input_path [String] Input GZIP file path
        # @param output_path [String] Output file path
        def decompress(input_path, output_path)
          File.open(input_path, "rb") do |input|
            File.open(output_path, "wb") do |output|
              decompress_stream(input, output)
            end
          end
        end

        # Compress data stream with GZIP
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @param options [Hash] Compression options
        def compress_stream(input_io, output_io, options = {})
          input_data = input_io.read
          level = options[:level] || Zlib::DEFAULT_COMPRESSION
          mtime = options[:mtime] || Time.now
          original_name = options[:original_name]

          # Write GZIP header
          write_header(output_io, mtime, original_name)

          # RFC 1952 member: header + RAW deflate + CRC32/ISIZE footer.
          # The old implementation layered zlib's own GZIP wrapper
          # under this header (a second 1F 8B magic) — the gem's
          # reader tolerated it, but every standard gzip tool
          # rejected the output. Raw-window mode emits bare DEFLATE.
          deflate = Zlib::Deflate.new(level, -Zlib::MAX_WBITS)
          output_io.write(deflate.deflate(input_data, Zlib::FINISH))
          deflate.close

          # Write GZIP footer
          write_footer(output_io, input_data)
        end

        # Decompress GZIP stream
        #
        # @param input_io [IO] Input stream
        # @param output_io [IO] Output stream
        # @return [Hash] Metadata (original_name, mtime)
        def decompress_stream(input_io, output_io)
          data = input_io.read

          # Metadata comes from the header either way (cheap parse).
          metadata = read_header(StringIO.new(data))

          # The tier gets the WHOLE member (header + deflate + trailer)
          # — the Rust "gzip" name decodes the container end-to-end.
          decompressed = Backends.decompress("gzip", data, Backends::UNKNOWN_LENGTH) do
            body = StringIO.new(data)
            read_header(body) # skip past the header
            # Legacy double-header members (written before the RFC
            # 1952 fix) carry zlib's own 10-byte GZIP header here;
            # standard members carry bare DEFLATE.
            rest = body.read
            rest = rest.byteslice(10..) if rest.byteslice(0, 2) == "\x1F\x8B".b
            inflate = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            result = inflate.inflate(rest)
            inflate.close
            result
          end

          output_io.write(decompressed)

          metadata
        end

        private

        # Write GZIP header
        #
        # @param output [IO] Output stream
        # @param mtime [Time] Modification time
        # @param original_name [String, nil] Original filename
        def write_header(output, mtime, original_name = nil)
          flags = 0
          flags |= FNAME if original_name

          header = [
            0x1F, 0x8B,           # Magic
            CM_DEFLATE,           # Compression method
            flags,                # Flags
            mtime.to_i,           # Modification time
            0,                    # Extra flags
            OS_UNIX               # OS type
          ].pack("C C C C V C C")

          output.write(header)

          # Write original filename if present
          return unless original_name

          output.write(original_name)
          output.write("\0")
        end

        # Read GZIP header
        #
        # @param input [IO] Input stream
        # @return [Hash] Header metadata
        def read_header(input)
          magic = input.read(2)
          unless magic == GZIP_MAGIC
            raise Error, "Not a GZIP file (invalid magic bytes)"
          end

          cm = input.read(1).unpack1("C")
          unless cm == CM_DEFLATE
            raise Error, "Unsupported GZIP compression method: #{cm}"
          end

          flags = input.read(1).unpack1("C")
          mtime = Time.at(input.read(4).unpack1("V"))
          _xfl = input.read(1)
          _os = input.read(1)

          metadata = { mtime: mtime }

          # Read extra fields if present
          if flags.anybits?(FEXTRA)
            xlen = input.read(2).unpack1("v")
            input.read(xlen) # Skip extra data
          end

          # Read original filename if present
          if flags.anybits?(FNAME)
            name = +""
            loop do
              byte = input.read(1)
              break if byte == "\0"

              name << byte
            end
            metadata[:original_name] = name
          end

          # Read comment if present
          if flags.anybits?(FCOMMENT)
            loop do
              byte = input.read(1)
              break if byte == "\0"
            end
          end

          # Read header CRC if present
          input.read(2) if flags.anybits?(FHCRC)

          metadata
        end

        # Write GZIP footer
        #
        # @param output [IO] Output stream
        # @param uncompressed_data [String] Original uncompressed data
        def write_footer(output, uncompressed_data)
          crc32 = Zlib.crc32(uncompressed_data)
          size = uncompressed_data.bytesize & 0xFFFFFFFF

          footer = [crc32, size].pack("VV")
          output.write(footer)
        end
      end
    end
  end
end
