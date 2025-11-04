# frozen_string_literal: true

module Omnizip
  module Formats
    module Xz
      # XZ block header
      #
      # Block header contains:
      # - Header size (1 byte) - size in 4-byte blocks
      # - Block flags (1 byte)
      # - Compressed size (variable, optional)
      # - Uncompressed size (variable, optional)
      # - Filter flags (variable)
      # - Padding to 4-byte boundary
      # - CRC32 (4 bytes)
      class BlockHeader
        # Filter IDs
        FILTER_LZMA2 = 0x21

        attr_reader :compressed_size, :uncompressed_size, :filters

        # Initialize block header
        #
        # @param options [Hash] Header options
        def initialize(options = {})
          @compressed_size = options[:compressed_size]
          @uncompressed_size = options[:uncompressed_size]
          @filters = options[:filters] || [{ id: FILTER_LZMA2 }]
        end

        # Encode block header to bytes
        #
        # @return [String] Encoded header
        def encode
          # Block flags byte
          flags = 0
          flags |= 0x40 if @compressed_size
          flags |= 0x80 if @uncompressed_size

          # Number of filters (0 = 1 filter, 3 = 4 filters)
          filter_count = [@filters.size - 1, 3].min
          flags |= filter_count

          data = [flags].pack("C")

          # Add sizes if present (encoded as multibyte integers)
          if @compressed_size
            data << encode_multibyte_integer(@compressed_size)
          end

          if @uncompressed_size
            data << encode_multibyte_integer(@uncompressed_size)
          end

          # Add filter properties
          @filters.each do |filter|
            data << encode_filter(filter)
          end

          # Calculate header size (including size byte and CRC32)
          # Round up to 4-byte blocks
          header_size_bytes = 1 + data.bytesize + 4
          header_size_blocks = (header_size_bytes + 3) / 4

          # Add padding
          padding_size = (header_size_blocks * 4) - header_size_bytes
          data << ("\0" * padding_size) if padding_size > 0

          # Prepend header size
          full_header = [header_size_blocks].pack("C") + data

          # Append CRC32
          crc32 = Zlib.crc32(full_header)
          full_header + [crc32].pack("V")
        end

        # Decode block header from stream
        #
        # @param io [IO] Input stream
        # @return [BlockHeader] Decoded header
        def self.decode(io)
          header_size_blocks = io.read(1).unpack1("C")
          return nil if header_size_blocks.nil? || header_size_blocks.zero?

          header_size_bytes = header_size_blocks * 4

          # Read rest of header (excluding size byte and CRC32)
          header_data_size = header_size_bytes - 1 - 4
          header_data = io.read(header_data_size)

          # Read and verify CRC32
          crc32_expected = io.read(4).unpack1("V")
          full_header = [header_size_blocks].pack("C") + header_data
          crc32_actual = Zlib.crc32(full_header)

          unless crc32_expected == crc32_actual
            raise Error, "XZ block header CRC32 mismatch"
          end

          # Parse header data
          flags = header_data.unpack1("C")
          offset = 1

          options = {}

          # Read compressed size if present
          if (flags & 0x40) != 0
            options[:compressed_size], bytes_read =
              decode_multibyte_integer(header_data[offset..-1])
            offset += bytes_read
          end

          # Read uncompressed size if present
          if (flags & 0x80) != 0
            options[:uncompressed_size], bytes_read =
              decode_multibyte_integer(header_data[offset..-1])
            offset += bytes_read
          end

          # Parse filters
          filter_count = (flags & 0x03) + 1
          options[:filters] = []

          filter_count.times do
            filter, bytes_read = decode_filter(header_data[offset..-1])
            options[:filters] << filter
            offset += bytes_read
          end

          new(options)
        end

        private

        # Encode multibyte integer (VLI - Variable Length Integer)
        #
        # @param value [Integer] Value to encode
        # @return [String] Encoded bytes
        def encode_multibyte_integer(value)
          bytes = []
          loop do
            byte = value & 0x7F
            value >>= 7
            byte |= 0x80 if value > 0
            bytes << byte
            break if value.zero?
          end
          bytes.pack("C*")
        end

        # Decode multibyte integer
        #
        # @param data [String] Data to decode
        # @return [Array<Integer, Integer>] Value and bytes consumed
        def self.decode_multibyte_integer(data)
          value = 0
          shift = 0
          offset = 0

          loop do
            byte = data[offset].unpack1("C")
            value |= (byte & 0x7F) << shift
            offset += 1
            break if (byte & 0x80).zero?

            shift += 7
          end

          [value, offset]
        end

        # Encode filter
        #
        # @param filter [Hash] Filter specification
        # @return [String] Encoded filter
        def encode_filter(filter)
          filter_id = filter[:id] || FILTER_LZMA2
          props = filter[:properties] || ""

          # Encode filter ID as VLI
          id_bytes = encode_multibyte_integer(filter_id)

          # Encode properties size as VLI
          props_size_bytes = encode_multibyte_integer(props.bytesize)

          id_bytes + props_size_bytes + props
        end

        # Decode filter
        #
        # @param data [String] Data to decode
        # @return [Array<Hash, Integer>] Filter and bytes consumed
        def self.decode_filter(data)
          filter_id, offset = decode_multibyte_integer(data)

          props_size, bytes_read = decode_multibyte_integer(data[offset..-1])
          offset += bytes_read

          props = data[offset, props_size]
          offset += props_size

          filter = { id: filter_id }
          filter[:properties] = props unless props.empty?

          [filter, offset]
        end
      end
    end
  end
end