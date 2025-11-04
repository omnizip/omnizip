# frozen_string_literal: true

require_relative "compression_profile"

module Omnizip
  module Profile
    # Balanced compression profile
    #
    # Provides a good balance between compression speed and ratio.
    # Uses Deflate with level 6 (the default for most use cases).
    class BalancedProfile < CompressionProfile
      # Initialize balanced profile
      def initialize
        super(
          name: :balanced,
          algorithm: :deflate,
          level: 6,
          filter: nil,
          solid: false,
          description: "Balanced speed/compression (default)"
        )
      end

      # Balanced profile is suitable for all MIME types
      #
      # @param _mime_type [String] MIME type string
      # @return [Boolean] Always true
      def suitable_for?(_mime_type)
        true
      end
    end
  end
end
