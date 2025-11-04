# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "progress_reporter"

module Omnizip
  module Progress
    # Silent progress reporter that produces no output.
    #
    # This reporter is useful when you want to track progress internally
    # but don't want any visible output.
    class SilentReporter < ProgressReporter
      # Report progress (does nothing)
      #
      # @param _progress [ProgressTracker] Progress tracker (ignored)
      def report(_progress)
        # Intentionally does nothing
      end
    end
  end
end
