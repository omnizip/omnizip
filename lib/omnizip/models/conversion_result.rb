# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Model for format conversion results.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    # The percentage/speed keys serialize the derived methods; the
    # attribute names differ from the keys so the framework's
    # generated readers do not shadow the methods.
    class ConversionResult < Lutaml::Model::Serializable
      attribute :source_path, :string
      attribute :target_path, :string
      attribute :source_format, :symbol
      attribute :target_format, :symbol
      attribute :source_size, :integer
      attribute :target_size, :integer
      attribute :duration, :double
      attribute :entry_count, :integer
      attribute :warnings, :string, collection: true, default: []

      attribute :ratio, :double, method: :compression_ratio_value
      attribute :reduction_pct, :double, method: :size_reduction
      attribute :ratio_pct, :double, method: :size_ratio
      attribute :speed, :double, method: :processing_speed

      key_value do
        map "source_path", to: :source_path,
                           render_default: true, render_nil: true
        map "target_path", to: :target_path,
                           render_default: true, render_nil: true
        map "source_format", to: :source_format,
                             render_default: true, render_nil: true
        map "target_format", to: :target_format,
                             render_default: true, render_nil: true
        map "source_size", to: :source_size,
                           render_default: true, render_nil: true
        map "target_size", to: :target_size,
                           render_default: true, render_nil: true
        map "size_reduction", to: :reduction_pct,
                              render_default: true, render_nil: true
        map "size_ratio", to: :ratio_pct,
                          render_default: true, render_nil: true
        map "duration", to: :duration,
                        render_default: true, render_nil: true
        map "entry_count", to: :entry_count,
                           render_default: true, render_nil: true
        map "processing_speed", to: :speed,
                                render_default: true, render_nil: true
        map "warnings", to: :warnings,
                        render_default: true, render_nil: true
        map "compression_ratio", to: :ratio,
                                 render_default: true, render_nil: true
      end

      # lutaml-model 0.8.x does not render empty-string/empty-collection
      # defaults, so they are assigned explicitly to keep every key
      # present in the serialized shape.
      def initialize(attrs = {})
        super({ warnings: [] }.merge(attrs))
      end

      # Get size reduction percentage
      #
      # @return [Float] Size reduction as percentage
      def size_reduction
        return 0.0 if source_size.to_i.zero?

        ((source_size - target_size).to_f / source_size * 100).round(2)
      end

      # Get size ratio
      #
      # @return [Float] Target size as percentage of source size
      def size_ratio
        return 0.0 if source_size.to_i.zero?

        (target_size.to_f / source_size * 100).round(2)
      end

      # Check if conversion resulted in smaller file
      #
      # @return [Boolean] True if target is smaller
      def smaller?
        target_size < source_size
      end

      # Check if conversion resulted in larger file
      #
      # @return [Boolean] True if target is larger
      def larger?
        target_size > source_size
      end

      # Check if there were warnings
      #
      # @return [Boolean] True if warnings exist
      def warnings?
        !warnings.empty?
      end

      # Get average processing speed
      #
      # @return [Float] MB/s processing speed
      def processing_speed
        return 0.0 if duration.to_f.zero? || source_size.to_i.zero?

        speed = source_size / duration / 1_048_576.0
        rounded = speed.round(2)
        # Return actual speed if rounding would give 0 but speed is positive
        rounded.zero? && speed.positive? ? speed : rounded
      end

      # Compression ratio (0.0-1.0 fraction saved by compression)
      #
      # @return [Float]
      def compression_ratio_value
        return 0.0 if source_size.to_i.zero?

        (1.0 - (target_size.to_f / source_size)).round(4)
      end

      # Format as human-readable string
      #
      # @return [String] Formatted result
      def to_s
        "Converted #{source_path} (#{format_size(source_size)}) to " \
          "#{target_path} (#{format_size(target_size)}) in #{duration.round(2)}s. " \
          "#{size_reduction.positive? ? "Saved #{size_reduction.to_i}%" : "Increased #{(-size_reduction).to_i}%"}"
      end

      private

      def format_size(bytes)
        Omnizip::CliOutputFormatter.format_size(bytes)
      end
    end
  end
end
