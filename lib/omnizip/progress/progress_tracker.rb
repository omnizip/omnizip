# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "operation_progress"
require_relative "../eta"

module Omnizip
  module Progress
    # Central progress tracking coordinator.
    #
    # This class tracks operation progress, calculates rates and ETA,
    # and reports progress to configured reporters. It integrates the
    # OperationProgress model with ETA calculation.
    class ProgressTracker
      attr_reader :operation_progress, :eta_estimator, :reporters,
                  :update_interval, :last_report_time

      # Initialize a new progress tracker
      #
      # @param total_files [Integer] Total number of files to process
      # @param total_bytes [Integer] Total bytes to process
      # @param reporters [Array<ProgressReporter>] Progress reporters
      # @param update_interval [Float] Minimum seconds between reports
      # @param eta_strategy [Symbol] ETA estimation strategy
      def initialize(total_files:, total_bytes:, reporters: [],
                     update_interval: 0.5, eta_strategy: :exponential_smoothing)
        @operation_progress = OperationProgress.new(
          total_files: total_files,
          total_bytes: total_bytes,
        )
        @eta_estimator = ETA.create_estimator(eta_strategy)
        @reporters = Array(reporters)
        @update_interval = update_interval
        @last_report_time = Time.now - update_interval # Allow immediate first report
        @mutex = Mutex.new # Thread safety
      end

      # Update progress with new values
      #
      # @param files [Integer] Number of files completed
      # @param bytes [Integer] Number of bytes processed
      # @param current_file [String] Name of file currently processing
      def update(files:, bytes:, current_file: nil)
        @mutex.synchronize do
          # Update operation progress
          operation_progress.update(
            files: files,
            bytes: bytes,
            current_file: current_file,
          )

          # Add sample to ETA estimator
          eta_estimator.add_sample(
            bytes_processed: bytes,
            files_processed: files,
          )

          # Report if enough time has passed
          report_if_needed
        end
      end

      # Get current completion percentage
      #
      # @return [Float] Percentage complete (0.0-100.0)
      def percentage
        operation_progress.percentage
      end

      # Get number of files processed
      #
      # @return [Integer] Files processed
      def files_processed
        operation_progress.files_done
      end

      # Get number of bytes processed
      #
      # @return [Integer] Bytes processed
      def bytes_processed
        operation_progress.bytes_done
      end

      # Get current file being processed
      #
      # @return [String, nil] Current file name
      def current_file
        operation_progress.current_file
      end

      # Get processing rate in MB/s
      #
      # @return [Float] Megabytes per second
      def rate_mbps
        eta_estimator.rate_calculator.megabytes_per_second
      end

      # Get processing rate in bytes/s
      #
      # @return [Float] Bytes per second
      def rate_bps
        eta_estimator.rate_calculator.bytes_per_second
      end

      # Get formatted rate string
      #
      # @return [String] Formatted rate (e.g., "2.5 MB/s")
      def rate_formatted
        eta_estimator.rate_calculator.format_rate
      end

      # Get ETA in seconds
      #
      # @return [Float] Estimated seconds remaining
      def eta_seconds
        result = eta_estimator.estimate(operation_progress.remaining_bytes)
        result.seconds_remaining
      end

      # Get formatted ETA string
      #
      # @return [String] Formatted ETA (e.g., "2m 30s")
      def eta_formatted
        result = eta_estimator.estimate(operation_progress.remaining_bytes)
        result.formatted
      end

      # Get full ETA result with confidence
      #
      # @return [Models::ETAResult] Complete ETA result
      def eta_result
        eta_estimator.estimate(operation_progress.remaining_bytes)
      end

      # Force a progress report (regardless of interval)
      def report
        @mutex.synchronize do
          reporters.each { |reporter| reporter.report(self) }
          @last_report_time = Time.now
        end
      end

      # Add a reporter
      #
      # @param reporter [ProgressReporter] Reporter to add
      def add_reporter(reporter)
        @mutex.synchronize do
          @reporters << reporter
        end
      end

      # Remove a reporter
      #
      # @param reporter [ProgressReporter] Reporter to remove
      def remove_reporter(reporter)
        @mutex.synchronize do
          @reporters.delete(reporter)
        end
      end

      # Check if operation is complete
      #
      # @return [Boolean] true if complete
      def complete?
        operation_progress.complete?
      end

      # Get elapsed time
      #
      # @return [Float] Seconds elapsed
      def elapsed_seconds
        operation_progress.elapsed_seconds
      end

      private

      # Report progress if enough time has passed since last report
      def report_if_needed
        now = Time.now
        return unless now - last_report_time >= update_interval

        reporters.each { |reporter| reporter.report(self) }
        @last_report_time = now
      end
    end
  end
end
