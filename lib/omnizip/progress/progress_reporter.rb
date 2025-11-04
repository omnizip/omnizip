# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module Progress
    # Abstract base class for progress reporters.
    #
    # This class defines the interface for progress reporting strategies.
    # Subclasses implement specific reporting mechanisms (console, callback,
    # log file, etc.).
    #
    # @abstract Subclass and override {#report} to implement a reporter
    class ProgressReporter
      # Report progress to the output mechanism
      #
      # @param progress [ProgressTracker] Progress tracker with current state
      # @raise [NotImplementedError] if not implemented by subclass
      def report(progress)
        raise NotImplementedError, "#{self.class} must implement #report"
      end

      # Called when operation starts (optional hook)
      #
      # @param progress [ProgressTracker] Progress tracker
      def start(progress)
        # Optional hook for subclasses
      end

      # Called when operation completes (optional hook)
      #
      # @param progress [ProgressTracker] Progress tracker
      def finish(progress)
        # Optional hook for subclasses
      end
    end
  end
end
