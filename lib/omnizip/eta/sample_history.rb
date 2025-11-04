# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module ETA
    # Stores historical samples for ETA calculation.
    #
    # This class maintains a time-series of progress samples with a limited
    # size to avoid unbounded memory growth. It provides statistics on the
    # samples for rate calculation and trend analysis.
    class SampleHistory
      # Single sample data point
      Sample = Struct.new(:timestamp, :bytes_processed, :files_processed) do
        # Calculate bytes/second rate between two samples
        #
        # @param other [Sample] Earlier sample
        # @return [Float] Bytes per second
        def rate_since(other)
          time_diff = timestamp - other.timestamp
          return 0.0 if time_diff <= 0

          bytes_diff = bytes_processed - other.bytes_processed
          bytes_diff / time_diff
        end
      end

      attr_reader :max_size, :samples

      # Initialize a new sample history
      #
      # @param max_size [Integer] Maximum number of samples to retain
      def initialize(max_size: 100)
        @max_size = max_size
        @samples = []
      end

      # Add a new sample to the history
      #
      # @param bytes_processed [Integer] Total bytes processed so far
      # @param files_processed [Integer] Total files processed so far
      # @param timestamp [Time] Sample timestamp (defaults to now)
      def add_sample(bytes_processed:, files_processed:, timestamp: Time.now)
        sample = Sample.new(timestamp, bytes_processed, files_processed)
        @samples << sample

        # Trim oldest samples if we exceed max size
        @samples.shift if @samples.size > max_size
      end

      # Get the most recent sample
      #
      # @return [Sample, nil] Most recent sample or nil if empty
      def latest
        @samples.last
      end

      # Get the oldest sample
      #
      # @return [Sample, nil] Oldest sample or nil if empty
      def oldest
        @samples.first
      end

      # Get samples from a specific time window
      #
      # @param seconds [Float] Number of seconds to look back
      # @return [Array<Sample>] Samples within the time window
      def recent_samples(seconds)
        return [] if @samples.empty?

        cutoff_time = Time.now - seconds
        @samples.select { |s| s.timestamp >= cutoff_time }
      end

      # Calculate average rate over all samples
      #
      # @return [Float] Average bytes per second
      def average_rate
        return 0.0 if @samples.size < 2

        first = @samples.first
        last = @samples.last
        last.rate_since(first)
      end

      # Calculate average rate over recent time window
      #
      # @param seconds [Float] Time window in seconds
      # @return [Float] Average bytes per second over window
      def recent_rate(seconds = 10.0)
        recent = recent_samples(seconds)
        return 0.0 if recent.size < 2

        first = recent.first
        last = recent.last
        last.rate_since(first)
      end

      # Calculate standard deviation of recent rates
      #
      # @param window_size [Integer] Number of samples to use
      # @return [Float] Standard deviation of rates
      def rate_std_dev(window_size = 10)
        return 0.0 if @samples.size < 3

        recent = @samples.last([window_size, @samples.size].min)
        rates = []

        1.upto(recent.size - 1) do |i|
          rates << recent[i].rate_since(recent[i - 1])
        end

        return 0.0 if rates.empty?

        mean = rates.sum / rates.size
        variance = rates.map { |r| (r - mean)**2 }.sum / rates.size
        Math.sqrt(variance)
      end

      # Clear all samples
      def clear
        @samples.clear
      end

      # Get number of samples
      #
      # @return [Integer] Number of samples stored
      def size
        @samples.size
      end

      # Check if history is empty
      #
      # @return [Boolean] true if no samples
      def empty?
        @samples.empty?
      end
    end
  end
end
