# frozen_string_literal: true

module Omnizip
  module Profile
    # Base class for compression profiles
    #
    # A compression profile encapsulates a set of compression settings that
    # define how files should be compressed. This includes the algorithm,
    # compression level, filters, and other options.
    #
    # @abstract Subclass and override {#suitable_for?} to implement a custom
    #   profile
    class CompressionProfile
      attr_reader :name, :algorithm, :level, :filter, :solid, :description

      # Initialize a new compression profile
      #
      # @param name [Symbol] Profile name
      # @param algorithm [Symbol] Compression algorithm (:deflate, :lzma2,
      #   :ppmd7, etc.)
      # @param level [Integer] Compression level (0-9)
      # @param filter [Symbol, nil] Filter to apply (:bcj_x86, :bcj_arm, etc.)
      # @param solid [Boolean] Whether to use solid compression
      # @param description [String] Human-readable description
      def initialize(
        name:,
        algorithm:,
        level:,
        filter: nil,
        solid: false,
        description: ""
      )
        @name = name
        @algorithm = algorithm
        @level = level
        @filter = filter
        @solid = solid
        @description = description

        validate!
        freeze
      end

      # Apply this profile to compression options
      #
      # @param options [Hash] Existing compression options
      # @return [Hash] Updated compression options
      def apply_to(options)
        options = options.dup

        options[:algorithm] = algorithm
        options[:level] = level
        options[:filter] = resolve_filter(options[:file_type]) if filter
        options[:solid] = solid

        options
      end

      # Check if this profile is suitable for a given MIME type
      #
      # @param mime_type [String] MIME type string to check
      # @return [Boolean] true if this profile is suitable
      def suitable_for?(_mime_type)
        # Default implementation - subclasses should override
        true
      end

      # Get profile information as a hash
      #
      # @return [Hash] Profile properties
      def to_h
        {
          name: name,
          algorithm: algorithm,
          level: level,
          filter: filter,
          solid: solid,
          description: description,
        }
      end

      # String representation of the profile
      #
      # @return [String]
      def to_s
        "#{name} - #{description}"
      end

      # Inspect representation
      #
      # @return [String]
      def inspect
        "#<#{self.class.name} name=#{name} " \
          "algorithm=#{algorithm} level=#{level}>"
      end

      private

      # Validate profile settings
      #
      # @raise [ArgumentError] if settings are invalid
      def validate!
        validate_name!
        validate_algorithm!
        validate_level!
        validate_filter!
      end

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

      # Resolve filter based on MIME type
      #
      # @param mime_type [String, nil] MIME type string
      # @return [Symbol, nil] Resolved filter
      def resolve_filter(mime_type)
        return filter unless filter == :auto
        return nil unless mime_type

        # Auto-select BCJ filter based on MIME type
        # For executables, default to x86 architecture
        require_relative "../file_type/mime_classifier"
        if FileType::MimeClassifier.executable?(mime_type)
          :bcj_x86
        end
      end
    end
  end
end
