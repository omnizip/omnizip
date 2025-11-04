# frozen_string_literal: true

require_relative "compression_profile"

module Omnizip
  module Profile
    # Fast compression profile
    #
    # Optimizes for compression speed over compression ratio.
    # Uses Deflate with level 1 for minimal CPU usage.
    class FastProfile < CompressionProfile
      # Initialize fast profile
      def initialize
        super(
          name: :fast,
          algorithm: :deflate,
          level: 1,
          filter: nil,
          solid: false,
          description: "Fast compression, lower ratio"
        )
      end

      # Fast profile is suitable for all MIME types
      #
      # @param _mime_type [String] MIME type string
      # @return [Boolean] Always true
      def suitable_for?(_mime_type)
        true
      end
    end
  end
end
