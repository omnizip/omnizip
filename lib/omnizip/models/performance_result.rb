# frozen_string_literal: true

module Omnizip
  module Models
    # Represents the performance characteristics of a profiled operation
    class PerformanceResult
      attr_reader :operation_name, :total_time, :cpu_time, :wall_time,
                  :memory_allocated, :memory_retained, :object_allocations,
                  :gc_runs, :call_count, :timestamp

      def initialize(
        operation_name:,
        total_time: nil,
        cpu_time: nil,
        wall_time: nil,
        memory_allocated: nil,
        memory_retained: nil,
        object_allocations: nil,
        gc_runs: nil,
        call_count: nil,
        timestamp: Time.now
      )
        @operation_name = operation_name
        @total_time = total_time
        @cpu_time = cpu_time
        @wall_time = wall_time
        @memory_allocated = memory_allocated
        @memory_retained = memory_retained
        @object_allocations = object_allocations
        @gc_runs = gc_runs
        @call_count = call_count
        @timestamp = timestamp
      end

      def throughput_ops_per_second
        return nil unless call_count && total_time && total_time.positive?

        call_count.to_f / total_time
      end

      def average_time_per_operation
        return nil unless call_count && total_time && call_count.positive?

        total_time / call_count.to_f
      end

      def memory_per_operation
        return nil unless call_count && memory_allocated && call_count.positive?

        memory_allocated / call_count.to_f
      end

      def gc_pressure
        return nil unless gc_runs && total_time && total_time.positive?

        gc_runs.to_f / total_time
      end

      def to_h
        {
          operation_name: operation_name,
          total_time: total_time,
          cpu_time: cpu_time,
          wall_time: wall_time,
          memory_allocated: memory_allocated,
          memory_retained: memory_retained,
          object_allocations: object_allocations,
          gc_runs: gc_runs,
          call_count: call_count,
          throughput_ops_per_second: throughput_ops_per_second,
          average_time_per_operation: average_time_per_operation,
          memory_per_operation: memory_per_operation,
          gc_pressure: gc_pressure,
          timestamp: timestamp.iso8601
        }
      end
    end
  end
end