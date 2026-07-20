# frozen_string_literal: true

module Omnizip
  module Models
    # Options for converting between archive formats.
    #
    # Plain Ruby value object. (Track 13 of TODO.refactor recommends
    # migrating this to lutaml-model once symbol-typed attributes are
    # available.)
    class ConversionOptions
      VALID_FORMATS = %i[zip seven_zip 7z].freeze

      attr_accessor :source_format, :target_format, :compression,
                    :compression_level, :filter, :preserve_metadata,
                    :temp_directory, :solid, :delete_source

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
          delete_source: delete_source,
        }
      end

      def validate
        validate_format(target_format, "target")
        validate_format(source_format, "source") if source_format
        validate_compression_level

        true
      end

      private

      def validate_format(format, type)
        return if VALID_FORMATS.include?(format)

        raise ArgumentError, "Invalid #{type} format: #{format}. " \
                             "Valid formats: #{VALID_FORMATS.join(', ')}"
      end

      def validate_compression_level
        return if (1..9).cover?(compression_level)

        raise ArgumentError,
              "Invalid compression level: #{compression_level}. Must be 1-9"
      end
    end
  end
end
