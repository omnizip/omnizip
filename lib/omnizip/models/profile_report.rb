# frozen_string_literal: true

module Omnizip
  module Models
    # Represents an aggregated profiling report with hot path analysis
    class ProfileReport
      attr_reader :profile_name, :results, :hot_paths, :bottlenecks,
                  :timestamp, :metadata

      def initialize(
        profile_name:,
        results: [],
        hot_paths: [],
        bottlenecks: [],
        timestamp: Time.now,
        metadata: {}
      )
        @profile_name = profile_name
        @results = results
        @hot_paths = hot_paths
        @bottlenecks = bottlenecks
        @timestamp = timestamp
        @metadata = metadata
      end

      def total_execution_time
        results.filter_map(&:total_time).sum
      end

      def total_memory_allocated
        results.filter_map(&:memory_allocated).sum
      end

      def total_gc_runs
        results.filter_map(&:gc_runs).sum
      end

      def slowest_operations(limit: 5)
        results.select(&:total_time)
          .sort_by(&:total_time)
          .reverse
          .take(limit)
      end

      def memory_intensive_operations(limit: 5)
        results.select(&:memory_allocated)
          .sort_by(&:memory_allocated)
          .reverse
          .take(limit)
      end

      def add_result(result)
        @results << result
      end

      def add_hot_path(hot_path)
        @hot_paths << hot_path
      end

      def add_bottleneck(bottleneck)
        @bottlenecks << bottleneck
      end

      def to_h
        {
          profile_name: profile_name,
          timestamp: timestamp.iso8601,
          summary: {
            total_execution_time: total_execution_time,
            total_memory_allocated: total_memory_allocated,
            total_gc_runs: total_gc_runs,
            operation_count: results.size,
          },
          results: results.map(&:to_h),
          hot_paths: hot_paths,
          bottlenecks: bottlenecks,
          metadata: metadata,
        }
      end
    end
  end
end
