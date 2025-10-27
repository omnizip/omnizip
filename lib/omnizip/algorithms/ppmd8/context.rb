# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

require_relative "../ppmd7/context"

module Omnizip
  module Algorithms
    class PPMd8 < PPMdBase
      # PPMd8 Context - Enhanced version with Union types
      #
      # Represents a context node in the PPMd8 model tree.
      # PPMd8 uses optimized memory layout with Union types.
      class Context < PPMd7::Context
        include Constants

        attr_accessor :num_stats, :flags, :sum_freq, :glue_count

        def initialize(order, suffix)
          super
          @num_stats = 0
          @flags = 0
          @sum_freq = 0
          @glue_count = 0
        end

        # PPMd8-specific: Check if context needs memory restoration
        def needs_restoration?
          @glue_count >= GLUE_COUNT_THRESHOLD
        end
      end
    end
  end
end
