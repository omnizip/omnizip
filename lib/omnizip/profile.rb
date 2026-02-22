# frozen_string_literal: true

require_relative "profile/compression_profile"
require_relative "profile/profile_registry"
require_relative "profile/profile_detector"
require_relative "profile/custom_profile"
require_relative "profile/fast_profile"
require_relative "profile/balanced_profile"
require_relative "profile/maximum_profile"
require_relative "profile/text_profile"
require_relative "profile/binary_profile"
require_relative "profile/archive_profile"

module Omnizip
  # Compression profile management
  #
  # This module provides a high-level API for working with compression
  # profiles. Profiles encapsulate compression settings and allow users
  # to easily select optimal compression strategies for different file types.
  module Profile
    class << self
      # Get the global profile registry
      #
      # @return [ProfileRegistry] The global registry
      def registry
        @registry ||= ProfileRegistry.new.tap do |reg|
          register_built_in_profiles(reg)
        end
      end

      # Get a profile by name
      #
      # @param name [Symbol] Profile name
      # @return [CompressionProfile, nil] The profile or nil
      def get(name)
        registry.get(name)
      end

      # Define a custom profile
      #
      # @param name [Symbol] Profile name
      # @param base [Symbol, nil] Base profile to extend
      # @yield [builder] Yields a builder for profile configuration
      # @yieldparam builder [CustomProfile::Builder] The profile builder
      # @return [CustomProfile] The created profile
      #
      # @example Define a custom profile
      #   Omnizip::Profile.define(:my_profile) do |p|
      #     p.algorithm = :lzma2
      #     p.level = 7
      #     p.filter = :bcj_x86
      #     p.solid = true
      #     p.description = "My custom profile"
      #   end
      #
      # @example Extend an existing profile
      #   Omnizip::Profile.define(:my_fast, base: :fast) do |p|
      #     p.level = 2
      #     p.description = "Slightly better than fast"
      #   end
      def define(name, base: nil)
        base_profile = base ? registry.get(base) : nil
        builder = CustomProfile::Builder.new(name, base_profile)

        yield builder if block_given?

        builder.valid?
        profile = builder.build

        registry.register!(profile)
        profile
      end

      # List all available profile names
      #
      # @return [Array<Symbol>] List of profile names
      def list
        registry.names
      end

      # Get recommended profile for a file type
      #
      # @param file_type [String, Symbol] MIME type string or category symbol
      # @return [CompressionProfile, nil] Recommended profile
      def for_file_type(file_type)
        # If file_type is a symbol (category), find first suitable profile
        return find_profile_for_category(file_type) if file_type.is_a?(Symbol)

        # If file_type is a MIME string, find suitable profiles
        if file_type.is_a?(String)
          suitable = registry.suitable_for(file_type)
          return registry.get(:balanced) if suitable.empty?

          return select_best_profile_for_mime(suitable, file_type)
        end

        # Default to balanced
        registry.get(:balanced)
      end

      # Auto-detect optimal profile for a file
      #
      # @param file_path [String] Path to the file
      # @param options [Hash] Detection options
      # @return [CompressionProfile] Detected profile
      def detect(file_path, options = {})
        detector.detect(file_path, options)
      end

      # Get the profile detector
      #
      # @return [ProfileDetector] The detector instance
      def detector
        @detector ||= ProfileDetector.new(registry)
      end

      # Reset the global registry (mainly for testing)
      #
      # @return [void]
      def reset!
        @registry = nil
        @detector = nil
      end

      private

      # Register all built-in profiles
      #
      # @param registry [ProfileRegistry] Registry to populate
      # @return [void]
      def register_built_in_profiles(registry)
        registry.register(FastProfile.new)
        registry.register(BalancedProfile.new)
        registry.register(MaximumProfile.new)
        registry.register(TextProfile.new)
        registry.register(BinaryProfile.new)
        registry.register(ArchiveProfile.new)
      end

      # Find profile for a category symbol
      #
      # @param category [Symbol] File category
      # @return [CompressionProfile, nil] Recommended profile
      def find_profile_for_category(category)
        case category
        when :text, :document, :code
          registry.get(:text)
        when :executable
          registry.get(:binary)
        when :archive, :compressed
          registry.get(:archive)
        else
          registry.get(:balanced)
        end
      end

      # Select best profile from suitable candidates based on MIME type
      #
      # @param profiles [Array<CompressionProfile>] Suitable profiles
      # @param mime_type [String] MIME type string
      # @return [CompressionProfile] Best profile
      def select_best_profile_for_mime(profiles, mime_type)
        require_relative "file_type/mime_classifier"

        # Determine category from MIME type
        category = FileType::MimeClassifier.profile_category(mime_type)

        priority = case category
                   when :archive
                     %i[archive fast balanced]
                   when :text
                     %i[text balanced]
                   when :binary
                     %i[binary maximum balanced]
                   else
                     [:balanced]
                   end

        # Find first profile matching priority
        priority.each do |name|
          profile = profiles.find { |p| p.name == name }
          return profile if profile
        end

        # Return first suitable profile if none matched priority
        profiles.first
      end
    end
  end
end
