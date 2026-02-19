# frozen_string_literal: true

require_relative "packet"

module Omnizip
  module Parity
    module Models
      # PAR2 IFSC (Input File Slice Checksum) packet
      #
      # Contains checksums for individual data blocks of a file.
      # One IFSC packet contains checksums for ALL blocks of a file.
      #
      # Body structure:
      # - file_id (16 bytes): File identifier
      # - For each block:
      #   - block_hash (16 bytes): MD5 hash of block data
      #   - block_crc32 (4 bytes, L<): CRC32 of block data
      class IfscPacket < Packet
        # Packet type identifier
        PACKET_TYPE = "PAR 2.0\x00IFSC\x00\x00\x00\x00"

        # File identifier (16 bytes)
        attribute :file_id, :string

        # Array of block hashes (16 bytes MD5 each)
        attribute :block_hashes, :string, collection: true, default: -> { [] }

        # Array of block CRC32s (4 bytes each)
        attribute :block_crc32s, :integer, collection: true, default: -> { [] }

        # Initialize IFSC packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          super
          self.type = PACKET_TYPE
          self.block_hashes = [] if block_hashes.nil?
          self.block_crc32s = [] if block_crc32s.nil?
        end

        # Parse body data into attributes
        #
        # Body format:
        # - file_id: 16 bytes
        # - For each block:
        #   - block_hash: 16 bytes
        #   - block_crc32: 4 bytes (L<)
        def parse_body
          return if body_data.nil? || body_data.empty?
          return if body_data.bytesize < 16

          pos = 0

          # Read file_id (16 bytes)
          self.file_id = body_data[pos, 16]
          pos += 16

          # Read all blocks (each is 16 bytes hash + 4 bytes CRC = 20 bytes)
          self.block_hashes = []
          self.block_crc32s = []

          while pos + 20 <= body_data.bytesize
            # Read block_hash (16 bytes)
            block_hash = body_data[pos, 16]
            pos += 16

            # Read block_crc32 (4 bytes, little-endian unsigned 32-bit)
            block_crc32 = body_data[pos, 4].unpack1("L<")
            pos += 4

            block_hashes << block_hash
            block_crc32s << block_crc32
          end
        end

        # Build body data from attributes
        #
        # Constructs binary body data
        #
        # @return [String] Binary body data
        def build_body
          data = +""

          # Validate file_id is 16 bytes
          if file_id.bytesize != 16
            raise ArgumentError,
                  "file_id must be 16 bytes, got #{file_id.bytesize}"
          end

          # Write file_id
          data << file_id

          # Write all blocks
          block_hashes.each_with_index do |block_hash, i|
            # Validate block_hash is 16 bytes
            if block_hash.bytesize != 16
              raise ArgumentError,
                    "block_hash must be 16 bytes, got #{block_hash.bytesize}"
            end

            # Write block_hash
            data << block_hash

            # Write block_crc32 (4 bytes, little-endian)
            data << [block_crc32s[i]].pack("L<")
          end

          self.body_data = data
        end

        # Deprecated: for backward compatibility
        def block_hash
          block_hashes.first
        end

        # Deprecated: for backward compatibility
        def block_crc32
          block_crc32s.first
        end
      end
    end
  end
end
