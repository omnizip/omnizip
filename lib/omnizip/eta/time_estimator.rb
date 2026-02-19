# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module ETA
    # Abstract base class for time estimation strategies.
    #
    # This class defines the interface for ETA estimators and provides
    # common functionality. Subclasses implement specific estimation
    # algorithms (exponential smoothing, moving average, etc.).
    class TimeEstimator
      attr_reader :sample_history, :rate_calculator

      # Initialize a new time estimator
      #
      # @param sample_history [SampleHistory] History of samples
      # @param rate_calculator [RateCalculator] Rate calculator
      def initialize(sample_history: nil, rate_calculator: nil)
        @sample_history = sample_history || SampleHistory.new
        @rate_calculator = rate_calculator ||
          RateCalculator.new(sample_history: @sample_history)
      end

      # Add a sample to the history
      #
      # @param bytes_processed [Integer] Total bytes processed
      # @param files_processed [Integer] Total files processed
      # @param timestamp [Time] Sample timestamp
      def add_sample(bytes_processed:, files_processed:, timestamp: Time.now)
        sample_history.add_sample(
          bytes_processed: bytes_processed,
          files_processed: files_processed,
          timestamp: timestamp,
        )
      end

      # Estimate time remaining (to be implemented by subclasses)
      #
      # @param remaining_bytes [Integer] Bytes remaining to process
      # @return [Models::ETAResult] ETA result
      # @raise [NotImplementedError] if not implemented by subclass
      def estimate(remaining_bytes)
        raise NotImplementedError, "#{self.class} must implement #estimate"
      end

      # Format seconds as human-readable string
      #
      # @param seconds [Float] Seconds to format
      # @return [String] Formatted time (e.g., "2m 30s", "1h 15m")
      def format_time(seconds)
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

      # Calculate confidence interval based on rate variance
      #
      # @param estimated_seconds [Float] Estimated time in seconds
      # @param confidence_level [Float] Confidence level (0.95 = 95%)
      # @return [Array<Float>] [lower_bound, upper_bound] in seconds
      def confidence_interval(estimated_seconds, confidence_level: 0.95)
        return [0.0, 0.0] if sample_history.size < 3

        # Use standard deviation of rates to calculate confidence interval
        std_dev = sample_history.rate_std_dev
        current_rate = rate_calculator.bytes_per_second

        return [estimated_seconds, estimated_seconds] if current_rate.zero?

        # Calculate coefficient of variation
        cv = std_dev / current_rate

        # Z-score for confidence level (approximation)
        z_score = confidence_level >= 0.99 ? 2.576 : 1.96

        # Calculate interval as percentage of estimate
        margin = estimated_seconds * cv * z_score

        lower = [estimated_seconds - margin, 0.0].max
        upper = estimated_seconds + margin

        [lower, upper]
      end

      # Check if we have enough samples for reliable estimation
      #
      # @return [Boolean] true if enough samples
      def sufficient_samples?
        sample_history.size >= 3
      end
    end
  end
end
