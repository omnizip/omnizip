# frozen_string_literal: true

module Omnizip
  module Parity
    # PAR2 packet models for serialization and parsing
    #
    # Contains model classes for all PAR2 packet types:
    # - Packet: Base class for all packets
    # - MainPacket: Recovery set metadata
    # - FileDescriptionPacket: Protected file metadata
    # - IfscPacket: Input File Slice Checksums
    # - RecoverySlicePacket: Reed-Solomon recovery data
    # - CreatorPacket: Creator identification
    # - PacketRegistry: Registry for packet type dispatch
    module Models
      autoload :Packet, "omnizip/parity/models/packet"
      autoload :CreatorPacket, "omnizip/parity/models/creator_packet"
      autoload :FileDescriptionPacket,
               "omnizip/parity/models/file_description_packet"
      autoload :IfscPacket, "omnizip/parity/models/ifsc_packet"
      autoload :MainPacket, "omnizip/parity/models/main_packet"
      autoload :RecoverySlicePacket,
               "omnizip/parity/models/recovery_slice_packet"
      autoload :PacketRegistry, "omnizip/parity/models/packet_registry"
    end
  end
end
