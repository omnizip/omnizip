# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Aggregated profiling report with hot path analysis.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    # The +summary+ key serializes a nested Summary model built from
    # the report's aggregates; hot paths and bottlenecks are the
    # analyzer-supplied hashes.
    class ProfileReport < Lutaml::Model::Serializable
      # Aggregate block of {ProfileReport#to_hash}.
      class Summary < Lutaml::Model::Serializable
        attribute :total_execution_time, :double, default: 0.0
        attribute :total_memory_allocated, :integer, default: 0
        attribute :total_gc_runs, :integer, default: 0
        attribute :operation_count, :integer, default: 0

        key_value do
          map "total_execution_time", to: :total_execution_time,
                                      render_default: true, render_nil: true
          map "total_memory_allocated", to: :total_memory_allocated,
                                        render_default: true, render_nil: true
          map "total_gc_runs", to: :total_gc_runs,
                               render_default: true, render_nil: true
          map "operation_count", to: :operation_count,
                                 render_default: true, render_nil: true
        end
      end

      attribute :profile_name, :string
      attribute :results, PerformanceResult, collection: true, default: []
      attribute :hot_paths, :hash, collection: true, default: []
      attribute :bottlenecks, :hash, collection: true, default: []
      attribute :timestamp, :date_time, default: -> { Time.now }
      attribute :metadata, :hash, default: {}
      attribute :summary, Summary, method: :build_summary

      key_value do
        map "profile_name", to: :profile_name,
                            render_default: true, render_nil: true
        map "timestamp", to: :timestamp,
                         render_default: true, render_nil: true
        map "summary", to: :summary,
                       render_default: true, render_nil: true
        map "results", to: :results,
                       render_default: true, render_nil: true
        map "hot_paths", to: :hot_paths,
                         render_default: true, render_nil: true
        map "bottlenecks", to: :bottlenecks,
                           render_default: true, render_nil: true
        map "metadata", to: :metadata,
                        render_default: true, render_nil: true
      end

      # lutaml-model 0.8.x does not render empty-collection defaults,
      # so they are assigned explicitly to keep every key present.
      def initialize(attrs = {})
        super({ results: [], hot_paths: [], bottlenecks: [],
                metadata: {} }.merge(attrs))
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
        results << result
      end

      def add_hot_path(hot_path)
        hot_paths << hot_path
      end

      def add_bottleneck(bottleneck)
        bottlenecks << bottleneck
      end

      # Serialized aggregate block.
      #
      # @return [Summary]
      def build_summary
        Summary.new(
          total_execution_time: total_execution_time,
          total_memory_allocated: total_memory_allocated,
          total_gc_runs: total_gc_runs,
          operation_count: results.size,
        )
      end
    end
  end
end
