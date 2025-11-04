# frozen_string_literal: true

require_relative "../file_type/mime_classifier"

module Omnizip
  module Profile
    # Automatic profile detection based on file analysis
    #
    # This class analyzes files and recommends optimal compression profiles
    # based on MIME type detection and user preferences.
    class ProfileDetector
      # Initialize a new profile detector
      #
      # @param registry [ProfileRegistry] Profile registry to use
      def initialize(registry = nil)
        @registry = registry || Profile.registry
      end

      # Detect the optimal profile for a file
      #
      # @param file_path [String] Path to the file
      # @param options [Hash] Detection options
      # @option options [Symbol] :fallback Fallback profile if detection fails
      #   (default: :balanced)
      # @return [CompressionProfile] Recommended profile
      def detect(file_path, options = {})
        fallback = options[:fallback] || :balanced

        # Detect MIME type
        mime_type = detect_mime_type(file_path)

        # Find suitable profiles
        suitable = find_suitable_profiles(mime_type)

        # Return most appropriate profile or fallback to balanced
        select_best_profile(suitable, mime_type) ||
          @registry.get(fallback) ||
          @registry.get(:balanced)
      end

      # Detect MIME type using FileType detector
      #
      # @param file_path [String] Path to the file
      # @return [String, nil] MIME type string or nil
      def detect_mime_type(file_path)
        return nil unless File.exist?(file_path)

        Omnizip::FileType.detect(file_path)
      rescue StandardError
        nil
      end

      # Find profiles suitable for a MIME type
      #
      # @param mime_type [String, nil] MIME type string
      # @return [Array<CompressionProfile>] Suitable profiles
      def find_suitable_profiles(mime_type)
        return [] unless mime_type

        @registry.suitable_for(mime_type)
      end

      # Select the best profile from suitable candidates
      #
      # @param profiles [Array<CompressionProfile>] Suitable profiles
      # @param mime_type [String, nil] MIME type string
      # @return [CompressionProfile, nil] Best profile or nil
      def select_best_profile(profiles, mime_type)
        return nil if profiles.empty?
        return profiles.first if profiles.size == 1

        # Priority order for specific MIME types
        priority = profile_priority(mime_type)

        # Find first profile in priority order
        priority.each do |name|
          profile = profiles.find { |p| p.name == name }
          return profile if profile
        end

        # Return first suitable profile if none matched priority
        profiles.first
      end

      private

      # Get profile priority based on MIME type
      #
      # @param mime_type [String, nil] MIME type string
      # @return [Array<Symbol>] Priority-ordered profile names
      def profile_priority(mime_type)
        return [:balanced] unless mime_type

        # Use MimeClassifier to determine category
        category = FileType::MimeClassifier.profile_category(mime_type)

        case category
        when :text
          %i[text balanced]
        when :binary
          %i[binary maximum balanced]
        when :archive
          %i[archive fast balanced]
        else
          [:balanced]
        end
      end
    end
  end
end
