# frozen_string_literal: true

require_relative "compression_profile"
require_relative "../file_type/mime_classifier"

module Omnizip
  module Profile
    # Binary compression profile
    #
    # Optimized for compressing executable files.
    # Uses LZMA2 with BCJ filters to improve compression of executables.
    class BinaryProfile < CompressionProfile
      # Initialize binary profile
      def initialize
        super(
          name: :binary,
          algorithm: :lzma2,
          level: 6,
          filter: :bcj_x86,
          solid: false,
          description: "Optimized for executables"
        )
      end

      # Check if this profile is suitable for a MIME type
      #
      # @param mime_type [String] MIME type string
      # @return [Boolean] true if MIME type is executable
      def suitable_for?(mime_type)
        return true unless mime_type

        FileType::MimeClassifier.executable?(mime_type)
      end
    end
  end
end
