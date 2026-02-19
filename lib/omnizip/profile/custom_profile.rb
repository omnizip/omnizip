# frozen_string_literal: true

require_relative "compression_profile"

module Omnizip
  module Profile
    # Custom user-defined compression profile
    #
    # Allows users to create custom profiles with specific settings.
    # Supports builder pattern for fluent API and profile inheritance.
    class CustomProfile < CompressionProfile
      # Builder for creating custom profiles
      class Builder
        attr_accessor :name, :algorithm, :level, :filter, :solid, :description,
                      :base_profile

        # Initialize a new builder
        #
        # @param name [Symbol] Profile name
        # @param base_profile [CompressionProfile, nil] Base profile to extend
        def initialize(name, base_profile = nil)
          @name = name

          if base_profile
            # Inherit settings from base profile
            @algorithm = base_profile.algorithm
            @level = base_profile.level
            @filter = base_profile.filter
            @solid = base_profile.solid
            @description = base_profile.description
            @base_profile = base_profile
          else
            # Default settings
            @algorithm = :deflate
            @level = 6
            @filter = nil
            @solid = false
            @description = ""
            @base_profile = nil
          end
        end

        # Build the custom profile
        #
        # @return [CustomProfile] The built profile
        def build
          CustomProfile.new(
            name: name,
            algorithm: algorithm,
            level: level,
            filter: filter,
            solid: solid,
            description: description,
            base_profile: base_profile,
          )
        end

        # Validate builder settings
        #
        # @raise [ArgumentError] if settings are invalid
        # @return [Boolean] true if valid
        def valid?
          validate_name!
          validate_algorithm!
          validate_level!
          validate_filter!
          true
        end

        private

        # Validate profile name
        def validate_name!
          raise ArgumentError, "Profile name is required" if name.nil?
          return if name.is_a?(Symbol)

          raise ArgumentError, "Profile name must be a Symbol"
        end

        # Validate algorithm
        def validate_algorithm!
          return if algorithm.nil?
          return if algorithm.is_a?(Symbol)

          raise ArgumentError, "Algorithm must be a Symbol"
        end

        # Validate compression level
        def validate_level!
          return if level.nil?
          return if level.is_a?(Integer) && level >= 0 && level <= 9

          raise ArgumentError, "Level must be an Integer between 0 and 9"
        end

        # Validate filter
        def validate_filter!
          return if filter.nil?
          return if filter.is_a?(Symbol)

          raise ArgumentError, "Filter must be a Symbol or nil"
        end
      end

      attr_reader :base_profile

      # Initialize a custom profile
      #
      # @param name [Symbol] Profile name
      # @param algorithm [Symbol] Compression algorithm
      # @param level [Integer] Compression level (0-9)
      # @param filter [Symbol, nil] Filter to apply
      # @param solid [Boolean] Whether to use solid compression
      # @param description [String] Human-readable description
      # @param base_profile [CompressionProfile, nil] Base profile extended
      def initialize(
        name:,
        algorithm:,
        level:,
        filter: nil,
        solid: false,
        description: "",
        base_profile: nil
      )
        @base_profile = base_profile
        super(
          name: name,
          algorithm: algorithm,
          level: level,
          filter: filter,
          solid: solid,
          description: description
        )
      end

      # Check if this profile is suitable for a file type
      #
      # @param file_type [Omnizip::FileType::DetectionResult] File type
      # @return [Boolean] Delegates to base profile if available
      def suitable_for?(file_type)
        return base_profile.suitable_for?(file_type) if base_profile

        # Custom profiles are suitable for all file types by default
        true
      end

      # Convert to hash with base profile information
      #
      # @return [Hash] Profile properties including base
      def to_h
        hash = super
        hash[:base_profile] = base_profile.name if base_profile
        hash
      end
    end
  end
end
