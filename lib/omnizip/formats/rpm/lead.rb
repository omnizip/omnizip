# frozen_string_literal: true

module Omnizip
  module Formats
    module Rpm
      # RPM lead structure parser
      #
      # The lead is a 96-byte deprecated header at the start of RPM files.
      # It contains basic package identification but most information
      # is now stored in the main header.
      class Lead
        include Omnizip::Formats::Rpm::Constants

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

        # Initialize a parsed lead. All attributes are required; use
        # +Lead.parse(io)+ for the typical read path.
        def initialize(magic:, major_version:, minor_version:, type:,
                       architecture:, name:, os:, signature_type:,
                       length: LEAD_SIZE)
          @magic = magic
          @major_version = major_version
          @minor_version = minor_version
          @type = type
          @architecture = architecture
          @name = name
          @os = os
          @signature_type = signature_type
          @length = length
        end

        # Parse lead from IO
        #
        # @param io [IO] Input stream positioned at lead
        # @return [Lead] Parsed lead object
        # @raise [ArgumentError] If magic is invalid
        def self.parse(io)
          data = io.read(LEAD_SIZE)
          raise ArgumentError, "Failed to read RPM lead" unless data
          raise ArgumentError, "Truncated RPM lead" if data.bytesize < LEAD_SIZE

          # Unpack lead structure
          # A4 = 4-byte string (magic)
          # CC = 2 unsigned chars (major, minor)
          # n = big-endian short (type)
          # n = big-endian short (architecture)
          # A66 = 66-byte string (name)
          # n = big-endian short (os)
          # n = big-endian short (signature_type)
          # A16 = 16-byte reserved
          magic, major, minor, type, arch, name, os, sig_type = data.unpack("A4 CC n n A66 n n A16")

          new(
            magic: magic,
            major_version: major,
            minor_version: minor,
            type: type,
            architecture: arch,
            name: name.strip,
            os: os,
            signature_type: sig_type,
          ).tap(&:validate!)
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
