# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Rpm
      # RPM lead structure parser
      #
      # The lead is a 96-byte deprecated header at the start of RPM files.
      # It contains basic package identification but most information
      # is now stored in the main header.
      class Lead
        include Constants

        # @return [String] 4-byte magic
        attr_reader :magic

        # @return [Integer] Major version
        attr_reader :major_version

        # @return [Integer] Minor version
        attr_reader :minor_version

        # @return [Integer] Package type (binary=0, source=1)
        attr_reader :type

        # @return [Integer] Architecture number
        attr_reader :architecture

        # @return [String] Package name (66 bytes)
        attr_reader :name

        # @return [Integer] OS number
        attr_reader :os

        # @return [Integer] Signature type
        attr_reader :signature_type

        # @return [Integer] Total length (always 96)
        attr_reader :length

        # Parse lead from IO
        #
        # @param io [IO] Input stream positioned at lead
        # @return [Lead] Parsed lead object
        # @raise [ArgumentError] If magic is invalid
        def self.parse(io)
          data = io.read(LEAD_SIZE)
          raise ArgumentError, "Failed to read RPM lead" unless data
          raise ArgumentError, "Truncated RPM lead" if data.bytesize < LEAD_SIZE

          new.tap do |lead|
            lead.instance_variable_set(:@length, LEAD_SIZE)

            # Unpack lead structure
            # A4 = 4-byte string (magic)
            # CC = 2 unsigned chars (major, minor)
            # n = big-endian short (type)
            # n = big-endian short (architecture)
            # A66 = 66-byte string (name)
            # n = big-endian short (os)
            # n = big-endian short (signature_type)
            # A16 = 16-byte reserved
            fields = data.unpack("A4 CC n n A66 n n A16")

            lead.instance_variable_set(:@magic, fields[0])
            lead.instance_variable_set(:@major_version, fields[1])
            lead.instance_variable_set(:@minor_version, fields[2])
            lead.instance_variable_set(:@type, fields[3])
            lead.instance_variable_set(:@architecture, fields[4])
            lead.instance_variable_set(:@name, fields[5].strip)
            lead.instance_variable_set(:@os, fields[6])
            lead.instance_variable_set(:@signature_type, fields[7])

            lead.validate!
          end
        end

        # Validate lead structure
        #
        # @raise [ArgumentError] If validation fails
        def validate!
          if @magic.nil? || @magic.bytesize < 4
            raise ArgumentError, "Invalid RPM magic: missing or truncated"
          end

          unless @magic == LEAD_MAGIC
            raise ArgumentError,
                  format("Invalid RPM magic: 0x%08x (expected 0x%08x)",
                         @magic.unpack1("N"), LEAD_MAGIC.unpack1("N"))
          end

          unless [PACKAGE_BINARY, PACKAGE_SOURCE].include?(@type)
            raise ArgumentError, "Invalid RPM type: #{@type}"
          end
        end

        # Check if package is binary
        #
        # @return [Boolean]
        def binary?
          @type == PACKAGE_BINARY
        end

        # Check if package is source
        #
        # @return [Boolean]
        def source?
          @type == PACKAGE_SOURCE
        end

        # Get type name
        #
        # @return [Symbol] :binary or :source
        def type_name
          binary? ? :binary : :source
        end
      end
    end
  end
end
