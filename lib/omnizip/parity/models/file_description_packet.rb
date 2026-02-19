# frozen_string_literal: true

require_relative "packet"

module Omnizip
  module Parity
    module Models
      # PAR2 File Description packet
      #
      # Contains metadata about a protected file including hashes and filename.
      #
      # Body structure:
      # - file_id (16 bytes): MD5 hash identifying the file
      # - file_hash (16 bytes): MD5 hash of complete file content
      # - file_hash_16k (16 bytes): MD5 hash of first 16KB
      # - length (8 bytes, Q<): File size in bytes
      # - filename (variable): Null-terminated filename, padded to multiple of 4
      class FileDescriptionPacket < Packet
        # Packet type identifier
        PACKET_TYPE = "PAR 2.0\x00FileDesc"

        # File identifier (16 bytes MD5)
        attribute :file_id, :string

        # Full file hash (16 bytes MD5)
        attribute :file_hash, :string

        # First 16KB hash (16 bytes MD5)
        attribute :file_hash_16k, :string

        # File length in bytes
        attribute :length, :integer

        # Filename (without null terminator or padding)
        attribute :filename, :string

        # Initialize file description packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          super
          self.type = PACKET_TYPE
        end

        # Parse body data into attributes
        #
        # Body format:
        # - file_id: 16 bytes
        # - file_hash: 16 bytes
        # - file_hash_16k: 16 bytes
        # - length: 8 bytes (Q<)
        # - filename: null-terminated, padded to multiple of 4
        def parse_body
          return if body_data.nil? || body_data.empty?

          # Validate minimum size (16+16+16+8 = 56 bytes minimum)
          if body_data.bytesize < 56
            warn "FileDescriptionPacket body too short: #{body_data.bytesize} bytes"
            return
          end

          pos = 0

          # Read file_id (16 bytes)
          self.file_id = body_data[pos, 16]
          pos += 16

          # Read file_hash (16 bytes)
          self.file_hash = body_data[pos, 16]
          pos += 16

          # Read file_hash_16k (16 bytes)
          self.file_hash_16k = body_data[pos, 16]
          pos += 16

          # Read length (8 bytes, little-endian unsigned 64-bit)
          length_data = body_data[pos, 8]
          return if length_data.nil? || length_data.bytesize < 8

          self.length = length_data.unpack1("Q<")
          pos += 8

          # Read filename (null-terminated, remaining bytes)
          filename_data = body_data[pos..]
          self.filename = filename_data&.unpack1("Z*") || ""
        end

        # Build body data from attributes
        #
        # Constructs binary body data with proper padding
        #
        # @return [String] Binary body data
        def build_body
          data = +""

          # Validate file_id, file_hash, file_hash_16k are 16 bytes
          [file_id, file_hash, file_hash_16k].each_with_index do |hash, idx|
            field_name = %w[file_id file_hash file_hash_16k][idx]
            if hash.bytesize != 16
              raise ArgumentError,
                    "#{field_name} must be 16 bytes, got #{hash.bytesize}"
            end
          end

          # Write hashes
          data << file_id
          data << file_hash
          data << file_hash_16k

          # Write length (8 bytes, little-endian)
          data << [length].pack("Q<")

          # Write filename (null-terminated, padded to multiple of 4)
          data << filename
          data << "\x00"

          # Add padding to make total length multiple of 4
          padding = (4 - ((filename.bytesize + 1) % 4)) % 4
          data << ("\x00" * padding) if padding.positive?

          self.body_data = data
        end

        # Get basename of file
        #
        # @return [String] File basename
        def basename
          File.basename(filename)
        end
      end
    end
  end
end
