# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require_relative "progress_reporter"

module Omnizip
  module Progress
    # Progress reporter that calls a user-provided Ruby block.
    #
    # This reporter allows users to provide custom callbacks for
    # progress updates, enabling integration with web frameworks,
    # GUI applications, or custom logging systems.
    class CallbackReporter < ProgressReporter
      attr_reader :callback

      # Initialize a new callback reporter
      #
      # @param callback [Proc] Block to call with progress updates
      # @yield [progress] Yields progress tracker to the block
      def initialize(&callback)
        super()
        @callback = callback || proc { |_| }
      end

      # Report progress by calling the callback
      #
      # @param progress [ProgressTracker] Progress tracker with current state
      def report(progress)
        callback.call(progress)
      end
    end
  end
end
