# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "time_estimator"
require_relative "../models/eta_result"

module Omnizip
  module ETA
    # ETA estimator using exponential smoothing.
    #
    # This estimator uses exponential smoothing to give more weight to
    # recent samples while still considering historical data. This provides
    # a good balance between responsiveness and stability.
    #
    # The smoothing factor (alpha) determines how much weight to give to
    # new samples: 0.0 = ignore new data, 1.0 = only use new data.
    class ExponentialSmoothingEstimator < TimeEstimator
      attr_reader :smoothing_factor, :smoothed_rate

      # Initialize a new exponential smoothing estimator
      #
      # @param smoothing_factor [Float] Alpha value (0.0-1.0), default 0.3
      # @param sample_history [SampleHistory] History of samples
      # @param rate_calculator [RateCalculator] Rate calculator
      def initialize(smoothing_factor: 0.3, **options)
        super(**options)
        @smoothing_factor = smoothing_factor.clamp(0.0, 1.0)
        @smoothed_rate = nil
      end

      # Estimate time remaining using exponential smoothing
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

        # Update smoothed rate
        current_rate = rate_calculator.bytes_per_second

        @smoothed_rate = if @smoothed_rate.nil?
                           current_rate
                         else
                           (smoothing_factor * current_rate) +
                             ((1.0 - smoothing_factor) * @smoothed_rate)
                         end

        # Calculate ETA
        seconds_remaining = if @smoothed_rate.positive?
                              remaining_bytes / @smoothed_rate
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

      # Reset smoothed rate (e.g., when operation changes significantly)
      def reset
        @smoothed_rate = nil
      end

      private

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
