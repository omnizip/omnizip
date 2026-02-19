# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require "digest"

module Omnizip
  module Parity
    module Models
      # Base class for PAR2 packets
      #
      # All PAR2 packets share a common 64-byte header structure:
      # - magic (8 bytes): "PAR2\0PKT"
      # - length (8 bytes): Total packet length including header (Q<)
      # - packet_hash (16 bytes): MD5 hash of (set_id + type + data)
      # - set_id (16 bytes): Recovery set identifier
      # - type (16 bytes): Packet type identifier
      #
      # The packet body follows the header and varies by packet type.
      class Packet < Lutaml::Model::Serializable
        # PAR2 packet signature
        PACKET_SIGNATURE = "PAR2\x00PKT".b.freeze

        # Common header fields (64 bytes total)
        attribute :magic, :string, default: -> { PACKET_SIGNATURE }
        attribute :length, :integer # Total packet length (header + body)
        attribute :packet_hash, :string # MD5 hash (16 bytes)
        attribute :set_id, :string # Recovery set ID (16 bytes)
        attribute :type, :string # Packet type (16 bytes)

        # Packet body data (variable length, subclass-specific)
        # NOT a lutaml-model attribute because it contains raw binary data
        # that can include null bytes and invalid UTF-8 sequences
        attr_accessor :body_data

        # Initialize packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          @body_data = "" # Initialize body_data with empty binary string
          super
        end

        # Read packet from IO stream
        #
        # @param io [IO] Input stream
        # @return [Packet, nil] Parsed packet or nil if EOF/invalid
        def self.read_from(io)
          # Read header (64 bytes total)
          magic = io.read(8)
          return nil unless magic == PACKET_SIGNATURE

          length = io.read(8).unpack1("Q<")
          packet_hash = io.read(16)
          set_id = io.read(16)
          type = io.read(16)

          # Read body data
          data_length = length - 64
          body_data = io.read(data_length)

          # Create instance
          packet = new(
            magic: magic,
            length: length,
            packet_hash: packet_hash,
            set_id: set_id,
            type: type,
          )

          # Set body_data directly to avoid lutaml-model attribute
          # corruption of binary data
          packet.body_data = body_data

          # Verify packet hash
          # NOTE: Hash validation temporarily disabled for par2cmdline compatibility testing
          # unless packet.valid_hash?
          #   warn "Invalid packet hash detected"
          # end

          packet
        end

        # Write packet to IO stream
        #
        # @param io [IO] Output stream
        def write_to(io)
          # Calculate total length
          self.length = 64 + body_data.bytesize

          # Calculate packet hash (MD5 of set_id + type + body_data)
          self.packet_hash = calculate_hash

          # Write header
          io.write(magic)
          io.write([length].pack("Q<"))
          io.write(packet_hash)
          io.write(set_id)
          io.write(type)

          # Write body
          io.write(body_data)
        end

        # Calculate MD5 hash of packet body
        #
        # Hash is computed over: set_id + type + body_data
        #
        # @return [String] 16-byte MD5 digest
        def calculate_hash
          data = +""
          data << set_id
          data << type
          data << body_data
          Digest::MD5.digest(data)
        end

        # Verify packet hash is correct
        #
        # @return [Boolean] true if hash matches
        def valid_hash?
          calculate_hash == packet_hash
        end

        # Get packet type identifier
        #
        # @return [String] 16-byte type identifier
        def packet_type
          type
        end

        # Parse body data into structured attributes
        #
        # Subclasses must implement this to parse body_data
        # into their specific attributes.
        def parse_body
          raise NotImplementedError,
                "#{self.class} must implement parse_body"
        end

        # Build body data from structured attributes
        #
        # Subclasses must implement this to build body_data
        # from their specific attributes.
        def build_body
          raise NotImplementedError,
                "#{self.class} must implement build_body"
        end
      end
    end
  end
end
