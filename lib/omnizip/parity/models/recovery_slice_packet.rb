# frozen_string_literal: true

require_relative "packet"

module Omnizip
  module Parity
    module Models
      # PAR2 Recovery Slice packet
      #
      # Contains Reed-Solomon encoded recovery data for error correction.
      #
      # Body structure:
      # - exponent (4 bytes, L<): Recovery block exponent/index
      # - recovery_data (variable): Reed-Solomon encoded block data
      class RecoverySlicePacket < Packet
        # Packet type identifier
        PACKET_TYPE = "PAR 2.0\x00RecvSlic"

        # Recovery block exponent (4 bytes)
        attribute :exponent, :integer

        # Recovery data (variable length)
        attribute :recovery_data, :string, default: -> { "" }

        # Initialize recovery slice packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          super
          self.type = PACKET_TYPE
        end

        # Parse body data into attributes
        #
        # Body format:
        # - exponent: 4 bytes (L<)
        # - recovery_data: remainder
        def parse_body
          return if body_data.nil? || body_data.empty?
          return if body_data.bytesize < 4

          pos = 0

          # Read exponent (4 bytes, little-endian unsigned 32-bit)
          self.exponent = body_data[pos, 4].unpack1("L<")
          pos += 4

          # Read recovery data (remainder)
          self.recovery_data = body_data[pos..] || ""
        end

        # Build body data from attributes
        #
        # Constructs binary body data
        #
        # @return [String] Binary body data
        def build_body
          data = +""

          # Write exponent (4 bytes, little-endian)
          data << [exponent].pack("L<")

          # Write recovery data
          data << recovery_data

          self.body_data = data
        end

        # Get size of recovery data
        #
        # @return [Integer] Recovery data size in bytes
        def data_size
          recovery_data.bytesize
        end
      end
    end
  end
end
