# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "progress_reporter"
require_relative "progress_bar"

module Omnizip
  module Progress
    # Progress reporter that displays a progress bar in the console.
    #
    # This reporter uses ProgressBar to render a visual progress bar
    # in the terminal, with automatic TTY detection and color support.
    class ConsoleReporter < ProgressReporter
      attr_reader :progress_bar, :output

      # Initialize a new console reporter
      #
      # @param output [IO] Output stream (default: $stdout)
      # @param width [Integer] Bar width (auto-detect if nil)
      # @param use_color [Boolean] Enable color output
      def initialize(output: $stdout, width: nil, use_color: true)
        super()
        @output = output
        @progress_bar = ProgressBar.new(width: width, use_color: use_color)
        @started = false
      end

      # Report progress to console
      #
      # @param progress [ProgressTracker] Progress tracker with current state
      def report(progress)
        return unless output.tty?

        @started = true
        output.print progress_bar.render(progress)
        output.flush
      end

      # Called when operation starts
      #
      # @param _progress [ProgressTracker] Progress tracker
      def start(_progress)
        @started = false
      end

      # Called when operation completes
      #
      # @param _progress [ProgressTracker] Progress tracker
      def finish(_progress)
        return unless output.tty? && @started

        # Clear the progress bar and print newline
        output.print progress_bar.clear
        output.puts
        output.flush
      end
    end
  end
end
