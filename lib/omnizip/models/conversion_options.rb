# frozen_string_literal: true

module Omnizip
  module Models
    # Model for format conversion options
    class ConversionOptions
      attr_accessor :source_format, :target_format, :compression,
                    :compression_level, :filter, :preserve_metadata,
                    :temp_directory, :solid, :delete_source

      # Initialize conversion options
      # @param source_format [Symbol, nil] Source format (auto-detect if nil)
      # @param target_format [Symbol] Target format
      # @param compression [Symbol, nil] Compression algorithm
      # @param compression_level [Integer] Compression level (1-9)
      # @param filter [Symbol, nil] Filter to apply
      # @param preserve_metadata [Boolean] Preserve metadata
      # @param temp_directory [String, nil] Temporary directory
      # @param solid [Boolean] Use solid compression (7z only)
      # @param delete_source [Boolean] Delete source after conversion
      def initialize(
        source_format: nil,
        target_format: :seven_zip,
        compression: nil,
        compression_level: 5,
        filter: nil,
        preserve_metadata: true,
        temp_directory: nil,
        solid: true,
        delete_source: false
      )
        @source_format = source_format
        @target_format = target_format
        @compression = compression
        @compression_level = compression_level
        @filter = filter
        @preserve_metadata = preserve_metadata
        @temp_directory = temp_directory
        @solid = solid
        @delete_source = delete_source
      end

      # Convert to hash
      # @return [Hash] Options as hash
      def to_h
        {
          source_format: source_format,
          target_format: target_format,
          compression: compression,
          compression_level: compression_level,
          filter: filter,
          preserve_metadata: preserve_metadata,
          temp_directory: temp_directory,
          solid: solid,
          delete_source: delete_source
        }
      end

      # Validate options
      # @raise [ArgumentError] If options are invalid
      def validate
        validate_format(target_format, "target")
        validate_format(source_format, "source") if source_format
        validate_compression_level

        true
      end

      private

      def validate_format(format, type)
        valid_formats = [:zip, :seven_zip, :"7z"]
        return if valid_formats.include?(format)

        raise ArgumentError, "Invalid #{type} format: #{format}. " \
                            "Valid formats: #{valid_formats.join(', ')}"
      end

      def validate_compression_level
        return if (1..9).cover?(compression_level)

        raise ArgumentError, "Invalid compression level: #{compression_level}. Must be 1-9"
      end
    end
  end
end