# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "progress_reporter"

module Omnizip
  module Progress
    # Progress reporter that writes to a log file.
    #
    # This reporter writes timestamped progress updates to a log file,
    # useful for debugging, auditing, or monitoring long-running operations.
    class LogReporter < ProgressReporter
      attr_reader :log_file, :verbose

      # Initialize a new log reporter
      #
      # @param log_file [String, IO] Log file path or IO object
      # @param verbose [Boolean] Include detailed information
      def initialize(log_file:, verbose: false)
        super()
        @log_file = log_file.is_a?(String) ? File.open(log_file, "a") : log_file
        @verbose = verbose
        @owns_file = log_file.is_a?(String)
      end

      # Report progress to log file
      #
      # @param progress [ProgressTracker] Progress tracker with current state
      def report(progress)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")

        if verbose
          log_file.puts format(
            "[%s] Progress: %.1f%% (%d/%d files, %d/%d bytes) - %s - %s - ETA: %s",
            timestamp,
            progress.percentage,
            progress.files_processed,
            progress.operation_progress.total_files,
            progress.bytes_processed,
            progress.operation_progress.total_bytes,
            progress.current_file || "unknown",
            progress.rate_formatted,
            progress.eta_formatted
          )
        else
          log_file.puts format(
            "[%s] Progress: %.1f%% - %s",
            timestamp,
            progress.percentage,
            progress.current_file || "processing"
          )
        end

        log_file.flush
      end

      # Called when operation starts
      #
      # @param progress [ProgressTracker] Progress tracker
      def start(progress)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        log_file.puts format(
          "[%s] Started: %d files, %d bytes",
          timestamp,
          progress.operation_progress.total_files,
          progress.operation_progress.total_bytes
        )
        log_file.flush
      end

      # Called when operation completes
      #
      # @param progress [ProgressTracker] Progress tracker
      def finish(progress)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        log_file.puts format(
          "[%s] Completed in %.2fs",
          timestamp,
          progress.elapsed_seconds
        )
        log_file.flush

        # Close file if we opened it
        log_file.close if @owns_file
      end
    end
  end
end
