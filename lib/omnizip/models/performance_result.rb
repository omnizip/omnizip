# frozen_string: true

require "lutaml/model"

module Omnizip
  module Models
    # Represents the performance characteristics of a profiled operation.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    # The derived-rate keys serialize the calculation methods; attribute
    # names differ from the keys so generated readers do not shadow them.
    class PerformanceResult < Lutaml::Model::Serializable
      attribute :operation_name, :string
      attribute :total_time, :double
      attribute :cpu_time, :double
      attribute :wall_time, :double
      attribute :memory_allocated, :integer
      attribute :memory_retained, :integer
      attribute :object_allocations, :integer
      attribute :gc_runs, :integer
      attribute :call_count, :integer
      attribute :timestamp, :date_time, default: -> { Time.now }

      attribute :throughput, :double, method: :throughput_ops_per_second
      attribute :average_time, :double, method: :average_time_per_operation
      attribute :memory_per_op, :double, method: :memory_per_operation
      attribute :pressure, :double, method: :gc_pressure

      key_value do
        map "operation_name", to: :operation_name,
                              render_default: true, render_nil: true
        map "total_time", to: :total_time,
                          render_default: true, render_nil: true
        map "cpu_time", to: :cpu_time,
                        render_default: true, render_nil: true
        map "wall_time", to: :wall_time,
                         render_default: true, render_nil: true
        map "memory_allocated", to: :memory_allocated,
                                render_default: true, render_nil: true
        map "memory_retained", to: :memory_retained,
                               render_default: true, render_nil: true
        map "object_allocations", to: :object_allocations,
                                  render_default: true, render_nil: true
        map "gc_runs", to: :gc_runs,
                       render_default: true, render_nil: true
        map "call_count", to: :call_count,
                          render_default: true, render_nil: true
        map "throughput_ops_per_second", to: :throughput,
                                         render_default: true, render_nil: true
        map "average_time_per_operation", to: :average_time,
                                          render_default: true, render_nil: true
        map "memory_per_operation", to: :memory_per_op,
                                    render_default: true, render_nil: true
        map "gc_pressure", to: :pressure,
                           render_default: true, render_nil: true
        map "timestamp", to: :timestamp,
                         render_default: true, render_nil: true
      end

      def throughput_ops_per_second
        return nil unless call_count && total_time&.positive?

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
        return nil unless gc_runs && total_time&.positive?

        gc_runs.to_f / total_time
      end
    end
  end
end
