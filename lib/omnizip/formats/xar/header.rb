# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Xar
      # XAR archive header parser and builder
      #
      # The XAR header is 28 bytes (or 64 bytes for extended format):
      # - Bytes 0-3:   Magic number (0x78617221 = "xar!")
      # - Bytes 4-5:   Header size (little-endian)
      # - Bytes 6-7:   Format version (little-endian)
      # - Bytes 8-15:  TOC compressed size (big-endian uint64)
      # - Bytes 16-23: TOC uncompressed size (big-endian uint64)
      # - Bytes 24-27: Checksum algorithm (big-endian uint32)
      # - Bytes 28-63: (Optional) Checksum name for CKSUM_OTHER
      class Header
        include Constants

        attr_reader :magic, :header_size, :version, :toc_compressed_size,
                    :toc_uncompressed_size, :checksum_algorithm,
                    :checksum_name

        # Parse header from binary data
        #
        # @param data [String] Binary header data (28+ bytes)
        # @return [Header] Parsed header object
        # @raise [ArgumentError] If data is invalid
        def self.parse(data)
          raise ArgumentError, "Header data too short (#{data.bytesize} bytes)" if data.bytesize < HEADER_SIZE

          magic = data[0, 4].unpack1("N")
          # XAR spec: All binary values are big-endian (network byte order)
          header_size = data[4, 2].unpack1("n")  # big-endian
          version = data[6, 2].unpack1("n")      # big-endian
          toc_compressed_size = data[8, 8].unpack1("Q>") # big-endian uint64
          toc_uncompressed_size = data[16, 8].unpack1("Q>") # big-endian uint64
          checksum_algorithm = data[24, 4].unpack1("N")

          # Parse checksum name for custom algorithms
          checksum_name = nil
          if checksum_algorithm == CKSUM_OTHER && data.bytesize >= HEADER_SIZE_EX
            checksum_name = data[28, 36].strip
          end

          new(
            magic: magic,
            header_size: header_size,
            version: version,
            toc_compressed_size: toc_compressed_size,
            toc_uncompressed_size: toc_uncompressed_size,
            checksum_algorithm: checksum_algorithm,
            checksum_name: checksum_name,
          )
        end

        # Read header from file
        #
        # @param file [IO] File handle positioned at start
        # @return [Header] Parsed header
        def self.read(file)
          data = file.read(HEADER_SIZE_EX) # Read max possible size
          raise ArgumentError, "Failed to read header" unless data

          # Parse to get actual header size
          header = parse(data)

          # Seek back if we read too much
          if data.bytesize > header.header_size
            file.seek(header.header_size, ::IO::SEEK_SET)
          end

          header
        end

        # Initialize header
        #
        # @param magic [Integer] Magic number
        # @param header_size [Integer] Header size in bytes
        # @param version [Integer] Format version
        # @param toc_compressed_size [Integer] Compressed TOC size
        # @param toc_uncompressed_size [Integer] Uncompressed TOC size
        # @param checksum_algorithm [Integer] Checksum algorithm constant
        # @param checksum_name [String, nil] Checksum name for CKSUM_OTHER
        def initialize(magic: MAGIC,
                       header_size: HEADER_SIZE,
                       version: XAR_VERSION,
                       toc_compressed_size: 0,
                       toc_uncompressed_size: 0,
                       checksum_algorithm: CKSUM_SHA1,
                       checksum_name: nil)
          @magic = magic
          @header_size = checksum_algorithm == CKSUM_OTHER && checksum_name ? HEADER_SIZE_EX : header_size
          @version = version
          @toc_compressed_size = toc_compressed_size
          @toc_uncompressed_size = toc_uncompressed_size
          @checksum_algorithm = checksum_algorithm
          @checksum_name = checksum_name
        end

        # Validate header
        #
        # @return [Boolean] true if valid
        # @raise [ArgumentError] If header is invalid
        def validate!
          unless @magic == MAGIC
            raise ArgumentError, format("Invalid magic: 0x%08x (expected 0x%08x)", @magic, MAGIC)
          end

          unless @header_size >= HEADER_SIZE
            raise ArgumentError, "Header size too small: #{@header_size}"
          end

          unless @version == XAR_VERSION
            raise ArgumentError, "Unsupported version: #{@version}"
          end

          unless [CKSUM_NONE, CKSUM_SHA1, CKSUM_MD5, CKSUM_OTHER].include?(@checksum_algorithm)
            raise ArgumentError, "Unknown checksum algorithm: #{@checksum_algorithm}"
          end

          if @checksum_algorithm == CKSUM_OTHER && @checksum_name.to_s.strip.empty?
            raise ArgumentError, "Custom checksum requires checksum_name"
          end

          true
        end

        # Check if header is valid
        #
        # @return [Boolean] true if valid
        def valid?
          validate!
        rescue ArgumentError
          false
        end

        # Get checksum algorithm name
        #
        # @return [String] Checksum algorithm name
        def checksum_algorithm_name
          if @checksum_algorithm == CKSUM_OTHER
            @checksum_name || "unknown"
          else
            CHECKSUM_NAMES[@checksum_algorithm] || "unknown"
          end
        end

        # Get checksum size in bytes
        #
        # @return [Integer] Checksum size
        def checksum_size
          CHECKSUM_SIZES[checksum_algorithm_name] || 0
        end

        # Check if checksum is used
        #
        # @return [Boolean] true if checksum is used
        def checksum?
          @checksum_algorithm != CKSUM_NONE
        end

        # Serialize header to binary
        #
        # @return [String] Binary header data
        def to_bytes
          data = +""
          data << [@magic].pack("N")                    # 4 bytes, big-endian
          data << [@header_size].pack("v")              # 2 bytes, little-endian
          data << [@version].pack("v")                  # 2 bytes, little-endian
          data << [@toc_compressed_size].pack("Q>")     # 8 bytes, big-endian
          data << [@toc_uncompressed_size].pack("Q>")   # 8 bytes, big-endian
          data << [@checksum_algorithm].pack("N")       # 4 bytes, big-endian

          # Add checksum name for custom algorithms
          if @checksum_algorithm == CKSUM_OTHER && @checksum_name
            name_bytes = @checksum_name.to_s.encode("ASCII").ljust(36, "\x00")
            data << name_bytes[0, 36]
          end

          data
        end

        # Update TOC sizes
        #
        # @param compressed [Integer] Compressed TOC size
        # @param uncompressed [Integer] Uncompressed TOC size
        # @return [Header] self for chaining
        def update_toc_sizes(compressed, uncompressed)
          @toc_compressed_size = compressed
          @toc_uncompressed_size = uncompressed
          self
        end
      end
    end
  end
end
