# frozen_string_literal: true

require "benchmark"

module Omnizip
  class Profiler
    # Profiles method execution time and call counts
    class MethodProfiler
      def initialize
        @call_counts = Hash.new(0)
      end

      def profile(operation_name)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gc_stat_before = GC.stat

        result = yield

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gc_stat_after = GC.stat

        @call_counts[operation_name] += 1

        wall_time = end_time - start_time
        gc_runs = gc_stat_after[:count] - gc_stat_before[:count]

        Models::PerformanceResult.new(
          operation_name: operation_name,
          total_time: wall_time,
          wall_time: wall_time,
          gc_runs: gc_runs,
          call_count: @call_counts[operation_name]
        )
      ensure
        result
      end

      def reset!
        @call_counts.clear
      end

      def call_count(operation_name)
        @call_counts[operation_name]
      end

      def total_calls
        @call_counts.values.sum
      end
    end
  end
end