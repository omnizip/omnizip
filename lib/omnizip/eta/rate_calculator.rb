# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module ETA
    # Calculates processing rates from sample history.
    #
    # This class computes various rates (bytes/sec, files/sec) with
    # smoothing over a time window to reduce noise from fluctuations.
    class RateCalculator
      attr_reader :sample_history, :window_seconds

      # Initialize a new rate calculator
      #
      # @param sample_history [SampleHistory] History of samples
      # @param window_seconds [Float] Time window for rate calculation
      def initialize(sample_history:, window_seconds: 10.0)
        @sample_history = sample_history
        @window_seconds = window_seconds
      end

      # Calculate current bytes per second rate
      #
      # @return [Float] Bytes per second over recent window
      def bytes_per_second
        sample_history.recent_rate(window_seconds)
      end

      # Calculate current megabytes per second rate
      #
      # @return [Float] Megabytes per second
      def megabytes_per_second
        bytes_per_second / (1024.0 * 1024.0)
      end

      # Calculate current files per second rate
      #
      # @return [Float] Files per second over recent window
      def files_per_second
        recent = sample_history.recent_samples(window_seconds)
        return 0.0 if recent.size < 2

        first = recent.first
        last = recent.last

        time_diff = last.timestamp - first.timestamp
        return 0.0 if time_diff <= 0

        files_diff = last.files_processed - first.files_processed
        files_diff / time_diff
      end

      # Calculate instantaneous rate (last two samples)
      #
      # @return [Float] Bytes per second between last two samples
      def instantaneous_rate
        return 0.0 if sample_history.size < 2

        samples = sample_history.samples
        last = samples[-1]
        previous = samples[-2]

        last.rate_since(previous)
      end

      # Format bytes per second as human-readable string
      #
      # @param rate [Float] Rate in bytes/second
      # @return [String] Formatted rate (e.g., "2.5 MB/s")
      def format_rate(rate = bytes_per_second)
        return "0 B/s" if rate.zero?

        if rate < 1024
          "#{rate.round(1)} B/s"
        elsif rate < 1024 * 1024
          "#{(rate / 1024.0).round(1)} KB/s"
        elsif rate < 1024 * 1024 * 1024
          "#{(rate / (1024.0 * 1024.0)).round(1)} MB/s"
        else
          "#{(rate / (1024.0 * 1024.0 * 1024.0)).round(1)} GB/s"
        end
      end

      # Check if rate is stable (low variance)
      #
      # @param threshold [Float] Max coefficient of variation for stability
      # @return [Boolean] true if rate is stable
      def stable?(threshold: 0.2)
        return false if sample_history.size < 5

        mean_rate = bytes_per_second
        return true if mean_rate.zero? # No data = stable

        std_dev = sample_history.rate_std_dev
        coefficient_of_variation = std_dev / mean_rate

        coefficient_of_variation < threshold
      end
    end
  end
end
