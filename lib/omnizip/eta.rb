# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "eta/sample_history"
require_relative "eta/rate_calculator"
require_relative "eta/time_estimator"
require_relative "eta/exponential_smoothing_estimator"
require_relative "eta/moving_average_estimator"

module Omnizip
  # ETA (Estimated Time to Arrival) calculation module.
  #
  # This module provides time estimation capabilities for long-running
  # operations. It tracks historical progress samples and uses various
  # estimation strategies to predict completion time.
  #
  # @example Basic usage
  #   estimator = Omnizip::ETA.create_estimator(:exponential_smoothing)
  #   estimator.add_sample(bytes_processed: 1000, files_processed: 10)
  #   # ... more samples ...
  #   eta = estimator.estimate(remaining_bytes: 5000)
  #   puts "ETA: #{eta.formatted}"
  module ETA
    # Create a new time estimator
    #
    # @param strategy [Symbol] Estimation strategy (:exponential_smoothing, :moving_average)
    # @param options [Hash] Strategy-specific options
    # @return [TimeEstimator] Configured estimator
    def self.create_estimator(strategy = :exponential_smoothing, **options)
      case strategy
      when :exponential_smoothing
        ExponentialSmoothingEstimator.new(**options)
      when :moving_average
        MovingAverageEstimator.new(**options)
      else
        raise ArgumentError, "Unknown estimation strategy: #{strategy}"
      end
    end

    # Format seconds as human-readable time string
    #
    # @param seconds [Float] Seconds to format
    # @return [String] Formatted time (e.g., "2m 30s")
    def self.format_time(seconds)
      return "0s" if seconds <= 0
      return "∞" if seconds.infinite?

      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).floor
      secs = (seconds % 60).round

      parts = []
      parts << "#{hours}h" if hours.positive?
      parts << "#{minutes}m" if minutes.positive? || hours.positive?
      parts << "#{secs}s"

      parts.join(" ")
    end
  end
end
