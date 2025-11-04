# frozen_string_literal: true

require_relative "compression_profile"

module Omnizip
  module Profile
    # Maximum compression profile
    #
    # Optimizes for the best compression ratio regardless of time.
    # Uses LZMA2 with level 9 and solid compression for maximum compression.
    class MaximumProfile < CompressionProfile
      # Initialize maximum profile
      def initialize
        super(
          name: :maximum,
          algorithm: :lzma2,
          level: 9,
          filter: :auto,
          solid: true,
          description: "Maximum compression, slower"
        )
      end

      # Maximum profile is suitable for all MIME types
      #
      # @param _mime_type [String] MIME type string
      # @return [Boolean] Always true
      def suitable_for?(_mime_type)
        true
      end
    end
  end
end
