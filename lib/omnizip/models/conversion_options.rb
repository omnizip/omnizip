# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Options for converting between archive formats.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    class ConversionOptions < Lutaml::Model::Serializable
      VALID_FORMATS = %i[zip seven_zip 7z].freeze

      attribute :source_format, :symbol
      attribute :target_format, :symbol, default: :seven_zip
      attribute :compression, :symbol
      attribute :compression_level, :integer, default: 5
      attribute :filter, :symbol
      attribute :preserve_metadata, :boolean, default: true
      attribute :temp_directory, :string
      attribute :solid, :boolean, default: true
      attribute :delete_source, :boolean, default: false

      # Both flags on every field: render_default alone still drops a key that
      # was explicitly assigned nil, and Converter builds this object with
      # new(**options) straight from caller-supplied hashes.
      key_value do
        map "source_format", to: :source_format,
                             render_default: true, render_nil: true
        map "target_format", to: :target_format,
                             render_default: true, render_nil: true
        map "compression", to: :compression,
                           render_default: true, render_nil: true
        map "compression_level", to: :compression_level,
                                 render_default: true, render_nil: true
        map "filter", to: :filter,
                      render_default: true, render_nil: true
        map "preserve_metadata", to: :preserve_metadata,
                                 render_default: true, render_nil: true
        map "temp_directory", to: :temp_directory,
                              render_default: true, render_nil: true
        map "solid", to: :solid,
                     render_default: true, render_nil: true
        map "delete_source", to: :delete_source,
                             render_default: true, render_nil: true
      end

      # Validate that formats and compression level are in range.
      #
      # Named +validate_options!+ rather than +validate+ so it does not
      # shadow Lutaml::Model::Validation#validate(register:).
      #
      # @raise [ArgumentError] if any value is invalid
      # @return [Boolean] true if valid
      def validate_options!
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
