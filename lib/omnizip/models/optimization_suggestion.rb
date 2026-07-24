# frozen_string_literal: true

module Omnizip
  module Models
    # Represents a performance optimization suggestion based on profiling data
    class OptimizationSuggestion
      SEVERITY_LEVELS = %i[low medium high critical].freeze
      CATEGORIES = %i[
        memory cpu hotpath algorithm io gc allocation concurrency
      ].freeze

      attr_reader :title, :description, :severity, :category, :impact_estimate,
                  :implementation_effort, :related_operations, :code_locations,
                  :metrics

      def initialize(
        title:,
        description:,
        severity:,
        category:,
        impact_estimate: nil,
        implementation_effort: nil,
        related_operations: [],
        code_locations: [],
        metrics: {}
      )
        validate_severity!(severity)
        validate_category!(category)

        @title = title
        @description = description
        @severity = severity
        @category = category
        @impact_estimate = impact_estimate
        @implementation_effort = implementation_effort
        @related_operations = related_operations
        @code_locations = code_locations
        @metrics = metrics
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

      def to_h
        {
          title: title,
          description: description,
          severity: severity,
          category: category,
          impact_estimate: impact_estimate,
          implementation_effort: implementation_effort,
          priority_score: priority_score,
          related_operations: related_operations,
          code_locations: code_locations,
          metrics: metrics,
        }
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
