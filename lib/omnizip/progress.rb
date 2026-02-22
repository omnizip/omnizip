# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "progress/operation_progress"
require_relative "progress/progress_tracker"
require_relative "progress/progress_reporter"
require_relative "progress/silent_reporter"
require_relative "progress/callback_reporter"
require_relative "progress/log_reporter"
require_relative "progress/progress_bar"
require_relative "progress/console_reporter"

module Omnizip
  # Progress tracking module.
  #
  # This module provides real-time progress tracking for long-running
  # operations with multiple reporting strategies (console, callback,
  # log file, etc.) and integrated ETA calculation.
  #
  # @example Basic progress tracking
  #   tracker = Omnizip::Progress.track(total_files: 100, total_bytes: 1.gigabyte)
  #   # Update progress as work is done
  #   tracker.update(files: 10, bytes: 100.megabytes, current_file: "file.txt")
  #   puts tracker.percentage # => 10.0
  #   puts tracker.eta_formatted # => "2m 30s"
  #
  # @example With console progress bar
  #   tracker = Omnizip::Progress.track(
  #     total_files: 100,
  #     total_bytes: 1.gigabyte,
  #     reporter: :console
  #   )
  #
  # @example With custom callback
  #   tracker = Omnizip::Progress.track(
  #     total_files: 100,
  #     total_bytes: 1.gigabyte
  #   ) do |progress|
  #     puts "#{progress.percentage}% complete"
  #   end
  module Progress
    # Track an operation's progress
    #
    # @param total_files [Integer] Total number of files to process
    # @param total_bytes [Integer] Total bytes to process
    # @param reporter [Symbol, ProgressReporter, Array] Reporter(s) to use
    # @param update_interval [Float] Minimum seconds between reports
    # @param eta_strategy [Symbol] ETA estimation strategy
    # @yield [progress] Optional callback block for custom reporting
    # @return [ProgressTracker] Configured progress tracker
    def self.track(total_files:, total_bytes:, reporter: :auto,
                   update_interval: 0.5, eta_strategy: :exponential_smoothing,
                   &block)
      reporters = build_reporters(reporter, block)

      ProgressTracker.new(
        total_files: total_files,
        total_bytes: total_bytes,
        reporters: reporters,
        update_interval: update_interval,
        eta_strategy: eta_strategy,
      )
    end

    # Configure global progress settings
    #
    # @yield [config] Configuration block
    def self.configure
      yield configuration
    end

    # Get global configuration
    #
    # @return [Configuration] Configuration object
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Build reporters from various input formats
    #
    # @param reporter [Symbol, ProgressReporter, Array] Reporter specification
    # @param block [Proc] Optional callback block
    # @return [Array<ProgressReporter>] Array of reporters
    def self.build_reporters(reporter, block)
      reporters = []

      # Handle callback block
      reporters << CallbackReporter.new(&block) if block

      # Handle reporter parameter
      case reporter
      when :auto
        reporters << ConsoleReporter.new if $stdout.tty?
      when :console
        reporters << ConsoleReporter.new
      when :silent
        reporters << SilentReporter.new
      when Array
        reporters.concat(reporter)
      when ProgressReporter
        reporters << reporter
      when Symbol
        raise ArgumentError, "Unknown reporter type: #{reporter}"
      end

      # Default to silent if no reporters
      reporters << SilentReporter.new if reporters.empty?

      reporters
    end

    # Global configuration class
    class Configuration
      attr_accessor :default_reporter, :default_update_interval,
                    :default_eta_strategy

      def initialize
        @default_reporter = :auto
        @default_update_interval = 0.5
        @default_eta_strategy = :exponential_smoothing
      end
    end
  end
end
