# frozen_string_literal: true

require_relative "compression_profile"
require_relative "../file_type/mime_classifier"

module Omnizip
  module Profile
    # Archive compression profile
    #
    # For files that are already compressed.
    # Uses Store (no compression) to avoid wasting CPU time on files
    # that cannot be compressed further.
    class ArchiveProfile < CompressionProfile
      # Initialize archive profile
      def initialize
        super(
          name: :archive,
          algorithm: :store,
          level: 0,
          filter: nil,
          solid: false,
          description: "No compression (already compressed files)"
        )
      end

      # Check if this profile is suitable for a MIME type
      #
      # @param mime_type [String] MIME type string
      # @return [Boolean] true if MIME type is already compressed
      def suitable_for?(mime_type)
        return true unless mime_type

        # Suitable for archives and media files (already compressed)
        FileType::MimeClassifier.archive?(mime_type) ||
          FileType::MimeClassifier.media?(mime_type)
      end
    end
  end
end
