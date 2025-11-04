# frozen_string_literal: true

require_relative "compression_profile"
require_relative "../file_type/mime_classifier"

module Omnizip
  module Profile
    # Text compression profile
    #
    # Optimized for compressing text files.
    # Uses PPMd7 which excels at text compression through context modeling.
    class TextProfile < CompressionProfile
      # Initialize text profile
      def initialize
        super(
          name: :text,
          algorithm: :ppmd7,
          level: 6,
          filter: nil,
          solid: false,
          description: "Optimized for text files"
        )
      end

      # Check if this profile is suitable for a MIME type
      #
      # @param mime_type [String] MIME type string
      # @return [Boolean] true if MIME type is text-based
      def suitable_for?(mime_type)
        return true unless mime_type

        FileType::MimeClassifier.text?(mime_type)
      end
    end
  end
end
