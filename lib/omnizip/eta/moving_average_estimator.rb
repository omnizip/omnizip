# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "time_estimator"
require_relative "../models/eta_result"

module Omnizip
  module ETA
    # ETA estimator using simple moving average.
    #
    # This estimator calculates the average rate over recent samples and
    # uses that to estimate time remaining. Simpler than exponential
    # smoothing but may be less responsive to changes.
    class MovingAverageEstimator < TimeEstimator
      attr_reader :window_size

      # Initialize a new moving average estimator
      #
      # @param window_size [Integer] Number of recent samples to average
      # @param sample_history [SampleHistory] History of samples
      # @param rate_calculator [RateCalculator] Rate calculator
      def initialize(window_size: 10, **options)
        super(**options)
        @window_size = window_size
      end

      # Estimate time remaining using moving average
      #
      # @param remaining_bytes [Integer] Bytes remaining to process
      # @return [Models::ETAResult] ETA result with confidence interval
      def estimate(remaining_bytes)
        return zero_result if remaining_bytes <= 0

        unless sufficient_samples?
          return Models::ETAResult.new.tap do |result|
            result.seconds_remaining = 0.0
            result.formatted = "calculating..."
            result.confidence_lower = 0.0
            result.confidence_upper = 0.0
          end
        end

        # Get average rate over recent samples
        avg_rate = calculate_average_rate

        # Calculate ETA
        seconds_remaining = if avg_rate.positive?
                              remaining_bytes / avg_rate
                            else
                              Float::INFINITY
                            end

        # Calculate confidence interval
        lower, upper = confidence_interval(seconds_remaining)

        Models::ETAResult.new.tap do |result|
          result.seconds_remaining = seconds_remaining
          result.formatted = format_time(seconds_remaining)
          result.confidence_lower = lower
          result.confidence_upper = upper
        end
      end

      private

      # Calculate average rate over recent window
      #
      # @return [Float] Average bytes per second
      def calculate_average_rate
        samples = sample_history.samples
        return 0.0 if samples.size < 2

        # Get last N samples (or all if less than N)
        recent = samples.last([window_size, samples.size].min)
        return 0.0 if recent.size < 2

        # Calculate rate between first and last of window
        first = recent.first
        last = recent.last
        last.rate_since(first)
      end

      # Return zero result for completed operation
      #
      # @return [Models::ETAResult] Zero result
      def zero_result
        Models::ETAResult.new.tap do |result|
          result.seconds_remaining = 0.0
          result.formatted = "0s"
          result.confidence_lower = 0.0
          result.confidence_upper = 0.0
        end
      end
    end
  end
end
