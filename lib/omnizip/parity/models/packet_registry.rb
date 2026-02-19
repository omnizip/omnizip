# frozen_string_literal: true

require_relative "packet"
require_relative "main_packet"
require_relative "file_description_packet"
require_relative "ifsc_packet"
require_relative "recovery_slice_packet"
require_relative "creator_packet"

module Omnizip
  module Parity
    module Models
      # Registry for PAR2 packet types
      #
      # Maps 16-byte packet type identifiers to their corresponding
      # packet class implementations. Enables polymorphic packet
      # parsing based on type field.
      class PacketRegistry
        @registry = {}

        class << self
          # Register a packet type
          #
          # @param type_id [String] 16-byte type identifier
          # @param klass [Class] Packet class
          def register(type_id, klass)
            unless type_id.bytesize == 16
              raise ArgumentError,
                    "Type ID must be 16 bytes, got #{type_id.bytesize}"
            end

            @registry[type_id] = klass
          end

          # Get packet class for type identifier
          #
          # @param type_id [String] 16-byte type identifier
          # @return [Class, nil] Packet class or nil if not registered
          def get(type_id)
            @registry[type_id]
          end

          # Check if type is registered
          #
          # @param type_id [String] 16-byte type identifier
          # @return [Boolean] true if type is registered
          def registered?(type_id)
            @registry.key?(type_id)
          end

          # Get all registered packet types
          #
          # @return [Array<String>] Array of 16-byte type identifiers
          def types
            @registry.keys
          end

          # Parse packet from IO and return appropriate subclass
          #
          # Reads a packet header, determines the type, and returns
          # an instance of the appropriate packet subclass.
          #
          # @param io [IO] Input stream
          # @return [Packet, nil] Parsed packet or nil if EOF/unknown type
          def read_packet(io)
            # Read base packet
            packet = Packet.read_from(io)
            return nil unless packet

            # Look up packet class for this type
            packet_class = get(packet.type)

            # If unknown type, return base Packet
            return packet unless packet_class

            # Create specific packet type
            specific_packet = packet_class.new(
              magic: packet.magic,
              length: packet.length,
              packet_hash: packet.packet_hash,
              set_id: packet.set_id,
              type: packet.type,
            )

            # Set body_data directly (not a lutaml attribute)
            specific_packet.body_data = packet.body_data

            # Parse body into structured fields
            specific_packet.parse_body

            specific_packet
          end

          # Clear all registrations (primarily for testing)
          def clear!
            @registry.clear
          end
        end

        # Register all standard PAR2 packet types
        register(MainPacket::PACKET_TYPE, MainPacket)
        register(FileDescriptionPacket::PACKET_TYPE, FileDescriptionPacket)
        register(IfscPacket::PACKET_TYPE, IfscPacket)
        register(RecoverySlicePacket::PACKET_TYPE, RecoverySlicePacket)
        register(CreatorPacket::PACKET_TYPE, CreatorPacket)
      end
    end
  end
end
