# frozen_string_literal: true

require_relative "packet"

module Omnizip
  module Parity
    module Models
      # PAR2 Creator packet
      #
      # Contains information about the tool that created the PAR2 file.
      # This packet is optional but recommended for identification.
      #
      # Body structure:
      # - creator_string (variable): Null-terminated string identifying the tool
      class CreatorPacket < Packet
        # Packet type identifier
        PACKET_TYPE = "PAR 2.0\x00Creator\x00"

        # Creator identification string (without null terminator)
        attribute :creator_string, :string, default: -> { "Omnizip PAR2" }

        # Initialize creator packet
        #
        # @param attributes [Hash] Packet attributes
        def initialize(**attributes)
          super
          self.type = PACKET_TYPE
        end

        # Parse body data into attributes
        #
        # Body format:
        # - creator_string: null-terminated string
        def parse_body
          return if body_data.nil? || body_data.empty?

          # Read creator string (null-terminated)
          self.creator_string = body_data.unpack1("Z*")
        end

        # Build body data from attributes
        #
        # Constructs binary body data with null terminator
        #
        # @return [String] Binary body data
        def build_body
          data = +""

          # Write creator string (null-terminated)
          data << creator_string
          data << "\x00"

          self.body_data = data
        end

        # Get creator tool name
        #
        # @return [String] Creator tool name
        def tool_name
          creator_string.split.first || creator_string
        end

        # Get creator version if available
        #
        # @return [String, nil] Version string or nil
        def version
          parts = creator_string.split
          parts.size > 1 ? parts[1..].join(" ") : nil
        end
      end
    end
  end
end
