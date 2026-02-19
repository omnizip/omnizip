# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module Models
    # Model representing progress tracking options.
    #
    # This class encapsulates configuration for progress tracking,
    # including reporter type, update interval, and display preferences.
    class ProgressOptions
      attr_accessor :reporter, :update_interval, :show_rate,
                    :show_eta, :show_files, :show_bytes

      def initialize
        @reporter = "auto"
        @update_interval = 0.5
        @show_rate = true
        @show_eta = true
        @show_files = true
        @show_bytes = true
      end

      def to_h
        {
          reporter: @reporter,
          update_interval: @update_interval,
          show_rate: @show_rate,
          show_eta: @show_eta,
          show_files: @show_files,
          show_bytes: @show_bytes,
        }.compact
      end
    end
  end
end
