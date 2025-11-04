# frozen_string_literal: true

module Omnizip
  class Profiler
    # Profiles memory allocation and retention
    class MemoryProfiler
      def initialize
        @call_counts = Hash.new(0)
      end

      def profile(operation_name)
        GC.start
        GC.disable

        gc_stat_before = GC.stat
        objspace_before = ObjectSpace.count_objects

        yield

        objspace_after = ObjectSpace.count_objects
        gc_stat_after = GC.stat

        GC.enable

        @call_counts[operation_name] += 1

        # Calculate memory metrics
        total_allocated = gc_stat_after[:total_allocated_objects] -
                          gc_stat_before[:total_allocated_objects]
        total_freed = gc_stat_after[:total_freed_objects] -
                      gc_stat_before[:total_freed_objects]

        # Object allocation delta
        objspace_after[:TOTAL]
        objspace_before[:TOTAL]

        # Estimate memory based on object allocations
        # Average Ruby object is ~40 bytes
        estimated_memory = total_allocated * 40

        Models::PerformanceResult.new(
          operation_name: operation_name,
          memory_allocated: estimated_memory,
          memory_retained: (total_allocated - total_freed) * 40,
          object_allocations: total_allocated,
          gc_runs: 0,
          call_count: @call_counts[operation_name]
        )
      ensure
        GC.enable
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
