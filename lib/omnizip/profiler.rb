# frozen_string_literal: true

require_relative "models/performance_result"
require_relative "models/profile_report"
require_relative "models/optimization_suggestion"

module Omnizip
  # Main profiler interface using Strategy pattern for different profiling approaches
  class Profiler
    attr_reader :report, :enabled

    def initialize(profile_name: "default", enabled: true)
      @profile_name = profile_name
      @enabled = enabled
      @report = Models::ProfileReport.new(profile_name: profile_name)
      @profilers = {}
    end

    # Register a profiler strategy
    def register_profiler(name, profiler)
      @profilers[name] = profiler
    end

    # Profile a block of code with the specified profiler strategy
    def profile(operation_name, profiler_type: :method, &block)
      return yield unless enabled

      profiler = @profilers[profiler_type]
      unless profiler
        raise ArgumentError,
              "Unknown profiler type: #{profiler_type}"
      end

      result = profiler.profile(operation_name, &block)
      @report.add_result(result)
      result
    end

    # Profile a method call with automatic naming
    def profile_method(object, method_name, *args, profiler_type: :method,
                       **kwargs)
      operation_name = "#{object.class}##{method_name}"
      profile(operation_name, profiler_type: profiler_type) do
        object.public_send(method_name, *args, **kwargs)
      end
    end

    # Analyze collected results and identify hot paths
    def analyze_hot_paths(threshold_percentage: 10.0)
      total_time = report.total_execution_time
      return [] if total_time.zero?

      threshold_time = total_time * (threshold_percentage / 100.0)

      hot_operations = report.results.select do |result|
        result.total_time && result.total_time >= threshold_time
      end

      hot_operations.each do |op|
        @report.add_hot_path(
          operation: op.operation_name,
          time: op.total_time,
          percentage: (op.total_time / total_time) * 100,
        )
      end

      hot_operations
    end

    # Identify performance bottlenecks
    def identify_bottlenecks
      bottlenecks = []

      # Memory bottlenecks
      memory_intensive = report.memory_intensive_operations(limit: 3)
      memory_intensive.each do |op|
        bottlenecks << {
          type: :memory,
          operation: op.operation_name,
          allocated: op.memory_allocated,
          severity: calculate_memory_severity(op),
        }
        @report.add_bottleneck(bottlenecks.last)
      end

      # CPU bottlenecks
      cpu_intensive = report.slowest_operations(limit: 3)
      cpu_intensive.each do |op|
        bottlenecks << {
          type: :cpu,
          operation: op.operation_name,
          time: op.total_time,
          severity: calculate_cpu_severity(op),
        }
        @report.add_bottleneck(bottlenecks.last)
      end

      # GC pressure bottlenecks
      high_gc = report.results.select do |r|
        r.gc_pressure && r.gc_pressure > 1.0
      end
      high_gc.each do |op|
        bottlenecks << {
          type: :gc,
          operation: op.operation_name,
          gc_pressure: op.gc_pressure,
          severity: :high,
        }
        @report.add_bottleneck(bottlenecks.last)
      end

      bottlenecks
    end

    # Generate optimization suggestions based on profiling data
    def generate_suggestions
      # Analyze hot paths for optimization opportunities
      suggestions = analyze_hot_paths.map do |hot_op|
        Models::OptimizationSuggestion.new(
          title: "Optimize hot path: #{hot_op.operation_name}",
          description: "Operation consuming #{hot_op.total_time}s " \
                       "(#{((hot_op.total_time / report.total_execution_time) * 100).round(1)}% of total time)",
          severity: :high,
          category: :hotpath,
          impact_estimate: hot_op.total_time / report.total_execution_time,
          related_operations: [hot_op.operation_name],
          metrics: { time: hot_op.total_time },
        )
      end

      # Analyze memory usage
      report.memory_intensive_operations(limit: 3).each do |mem_op|
        next unless mem_op.memory_allocated > 1_000_000 # > 1MB

        suggestions << Models::OptimizationSuggestion.new(
          title: "Reduce memory allocation: #{mem_op.operation_name}",
          description: "Operation allocating #{format_bytes(mem_op.memory_allocated)}",
          severity: calculate_memory_severity(mem_op),
          category: :memory,
          impact_estimate: mem_op.memory_allocated / report.total_memory_allocated.to_f,
          related_operations: [mem_op.operation_name],
          metrics: { memory_allocated: mem_op.memory_allocated },
        )
      end

      suggestions.sort_by(&:priority_score).reverse
    end

    # Enable profiling
    def enable!
      @enabled = true
    end

    # Disable profiling
    def disable!
      @enabled = false
    end

    # Reset profiler state
    def reset!
      @report = Models::ProfileReport.new(profile_name: @profile_name)
    end

    private

    def calculate_memory_severity(operation)
      return :low unless operation.memory_allocated

      mb = operation.memory_allocated / (1024.0 * 1024.0)
      case mb
      when 0...1 then :low
      when 1...10 then :medium
      when 10...50 then :high
      else :critical
      end
    end

    def calculate_cpu_severity(operation)
      return :low unless operation.total_time

      case operation.total_time
      when 0...0.1 then :low
      when 0.1...1.0 then :medium
      when 1.0...5.0 then :high
      else :critical
      end
    end

    def format_bytes(bytes)
      return "0 B" if bytes.zero?

      units = %w[B KB MB GB]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024.0 && unit_index < units.size - 1
        size /= 1024.0
        unit_index += 1
      end

      format("%.2f %s", size, units[unit_index])
    end
  end
end
