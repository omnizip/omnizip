# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module Progress
    # Visual progress bar for terminal output.
    #
    # This class renders a progress bar with percentage, file counts,
    # rate, and ETA information. It supports color output and automatic
    # width detection.
    class ProgressBar
      attr_reader :width, :use_color

      # Initialize a new progress bar
      #
      # @param width [Integer] Bar width in characters (auto-detect if nil)
      # @param use_color [Boolean] Enable color output
      def initialize(width: nil, use_color: true)
        @width = width || detect_terminal_width
        @use_color = use_color && color_supported?
      end

      # Render progress bar string
      #
      # @param progress [ProgressTracker] Progress tracker
      # @return [String] Formatted progress bar
      def render(progress)
        bar = build_bar(progress.percentage)
        info = build_info(progress)

        "\r#{bar} #{info}"
      end

      # Clear the progress bar line
      #
      # @return [String] Clear string
      def clear
        "\r#{" " * width}\r"
      end

      private

      # Build the progress bar component
      #
      # @param percentage [Float] Completion percentage (0.0-100.0)
      # @return [String] Progress bar string
      def build_bar(percentage)
        bar_width = 20
        filled = ((percentage / 100.0) * bar_width).round
        empty = bar_width - filled

        bar = "[#{"=" * filled}#{">" if filled.positive?}#{" " * [empty - 1,
                                                                  0].max}]"

        if use_color
          colorize(bar, :green)
        else
          bar
        end
      end

      # Build the info component (percentage, files, rate, ETA)
      #
      # @param progress [ProgressTracker] Progress tracker
      # @return [String] Info string
      def build_info(progress)
        parts = []

        # Percentage
        parts << format("%3.0f%%", progress.percentage)

        # File count
        parts << format(
          "(%d/%d files)",
          progress.files_processed,
          progress.operation_progress.total_files
        )

        # Current file (truncate if too long)
        if progress.current_file
          filename = truncate_filename(progress.current_file, 30)
          parts << filename
        end

        # Rate
        parts << progress.rate_formatted if progress.rate_bps.positive?

        # ETA
        eta = progress.eta_formatted
        parts << "ETA: #{eta}" unless eta == "calculating..."

        parts.join(" - ")
      end

      # Truncate filename to fit width
      #
      # @param filename [String] Filename to truncate
      # @param max_length [Integer] Maximum length
      # @return [String] Truncated filename
      def truncate_filename(filename, max_length)
        return filename if filename.length <= max_length

        "...#{filename[(-max_length + 3)..]}"
      end

      # Detect terminal width
      #
      # @return [Integer] Terminal width in characters
      def detect_terminal_width
        if ENV["COLUMNS"]
          ENV["COLUMNS"].to_i
        elsif $stdout.tty?
          begin
            require "io/console"
            $stdout.winsize[1]
          rescue LoadError, NoMethodError
            80 # Default fallback
          end
        else
          80
        end
      end

      # Check if terminal supports color
      #
      # @return [Boolean] true if color is supported
      def color_supported?
        return false unless $stdout.tty?
        return false if ENV["TERM"] == "dumb"

        true
      end

      # Colorize string with ANSI color codes
      #
      # @param text [String] Text to colorize
      # @param color [Symbol] Color name (:green, :yellow, :red, etc.)
      # @return [String] Colorized string
      def colorize(text, color)
        color_codes = {
          green: 32,
          yellow: 33,
          red: 31,
          blue: 34,
          cyan: 36
        }

        code = color_codes[color] || 0
        "\e[#{code}m#{text}\e[0m"
      end
    end
  end
end
