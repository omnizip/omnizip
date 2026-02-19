# frozen_string_literal: true

require_relative "packet"

module Omnizip
  module Parity
    module Models
      # PAR2 Main packet
      #
      # Contains recovery set metadata including block size and file IDs.
      #
      # Body structure:
      # - block_size (8 bytes, Q<): Size of each data block
      # - file_ids (16 bytes each): List of file IDs in the recovery set
      #
      # Note: In current Par2Creator implementation, the body includes
      # additional fields after block_size that are not part of the
      # standard PAR2 spec. This model follows the actual PAR2 spec.
      class MainPacket < Packet
        # Packet type identifier
        PACKET_TYPE = "PAR 2.0\x00Main\x00\x00\x00\x00"

        # Block size in bytes
        attribute :block_size, :integer

        # Array of 16-byte file IDs
        attribute :file_ids, :string, collection: true, default: -> { [] }

        # Initialize main packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          super
          self.type = PACKET_TYPE
        end

        # Parse body data into attributes
        #
        # Body format (PAR2 spec):
        # - block_size: 8 bytes (Q<)
        # - file_ids: 16 bytes each, until end of body
        #
        # par2cmdline variant also includes:
        # - file_count: 4 bytes (L<) after block_size
        # - then file_ids: 16 bytes each
        #
        # This method detects which format is used.
        def parse_body
          return if body_data.nil? || body_data.empty?

          pos = 0

          # Read block_size (8 bytes, little-endian unsigned 64-bit)
          self.block_size = body_data[pos, 8].unpack1("Q<")
          pos += 8

          # Detect format: check if next 4 bytes are a file_count
          remaining = body_data.bytesize - pos

          if remaining >= 4
            # Try to read potential file_count
            potential_count = body_data[pos, 4].unpack1("L<")
            expected_size = potential_count * 16

            # Check if this looks like par2cmdline format:
            # - Remaining bytes should be: 4 (count) + count * 16 (file_ids)
            # - Count should be reasonable (> 0, < 10000 for sanity)
            if remaining == (4 + expected_size) &&
                potential_count.positive? &&
                potential_count < 10_000
              # par2cmdline format detected
              pos += 4 # Skip the file_count field
            end
          end

          # Read file IDs (16 bytes each) until end of body
          self.file_ids = []
          while pos < body_data.bytesize
            file_id = body_data[pos, 16]
            break if file_id.nil? || file_id.bytesize < 16

            file_ids << file_id
            pos += 16
          end
        end

        # Build body data from attributes
        #
        # Constructs binary body data from block_size and file_ids
        #
        # @return [String] Binary body data
        def build_body
          data = +""

          # Write block_size (8 bytes, little-endian)
          data << [block_size].pack("Q<")

          # Write file IDs (16 bytes each)
          file_ids.each do |file_id|
            # Ensure file_id is exactly 16 bytes
            if file_id.bytesize != 16
              raise ArgumentError,
                    "File ID must be 16 bytes, got #{file_id.bytesize}"
            end
            data << file_id
          end

          self.body_data = data
        end

        # Get number of files in recovery set
        #
        # @return [Integer] File count
        def file_count
          file_ids.size
        end

        # Check if packet contains specific file ID
        #
        # @param file_id [String] 16-byte file ID to check
        # @return [Boolean] true if file ID is present
        def includes_file?(file_id)
          file_ids.include?(file_id)
        end
      end
    end
  end
end
