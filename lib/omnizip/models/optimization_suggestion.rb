# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Represents a performance optimization suggestion based on
    # profiling data.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    # The priority_score key serializes the derived #priority_score
    # method under a distinct attribute name.
    class OptimizationSuggestion < Lutaml::Model::Serializable
      SEVERITY_LEVELS = %i[low medium high critical].freeze
      CATEGORIES = %i[
        memory cpu hotpath algorithm io gc allocation concurrency
      ].freeze

      attribute :title, :string
      attribute :description, :string
      attribute :severity, :symbol
      attribute :category, :symbol
      attribute :impact_estimate, :double
      attribute :implementation_effort, :double
      attribute :related_operations, :string, collection: true, default: []
      attribute :code_locations, :string, collection: true, default: []
      attribute :metrics, :hash, default: {}

      attribute :priority, :double, method: :priority_score

      key_value do
        map "title", to: :title, render_default: true, render_nil: true
        map "description", to: :description,
                           render_default: true, render_nil: true
        map "severity", to: :severity, render_default: true, render_nil: true
        map "category", to: :category, render_default: true, render_nil: true
        map "impact_estimate", to: :impact_estimate,
                               render_default: true, render_nil: true
        map "implementation_effort", to: :implementation_effort,
                                     render_default: true, render_nil: true
        map "priority_score", to: :priority,
                              render_default: true, render_nil: true
        map "related_operations", to: :related_operations,
                                  render_default: true, render_nil: true
        map "code_locations", to: :code_locations,
                              render_default: true, render_nil: true
        map "metrics", to: :metrics, render_default: true, render_nil: true
      end

      # Severity and category are validated after the framework
      # constructor assigns the attributes. Empty-collection defaults
      # are assigned explicitly (lutaml-model 0.8.x drops them).
      def initialize(attrs = {})
        super({ related_operations: [], code_locations: [],
                metrics: {} }.merge(attrs))
        validate_severity!(severity)
        validate_category!(category)
      end

      def critical?
        severity == :critical
      end

      def high_priority?
        severity == :high || critical?
      end

      def priority_score
        severity_weight = SEVERITY_LEVELS.index(severity) + 1
        impact_weight = impact_estimate || 1.0
        effort_weight = implementation_effort ? (1.0 / implementation_effort) : 1.0

        severity_weight * impact_weight * effort_weight
      end

      private

      def validate_severity!(severity)
        return if SEVERITY_LEVELS.include?(severity)

        raise ArgumentError,
              "Invalid severity: #{severity}. " \
              "Must be one of: #{SEVERITY_LEVELS.join(', ')}"
      end

      def validate_category!(category)
        return if CATEGORIES.include?(category)

        raise ArgumentError,
              "Invalid category: #{category}. " \
              "Must be one of: #{CATEGORIES.join(', ')}"
      end
    end
  end
end
