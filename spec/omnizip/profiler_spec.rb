# frozen_string_literal: true

require "spec_helper"
require "omnizip/profiler"
require "omnizip/profiler/method_profiler"
require "omnizip/profiler/memory_profiler"
require "omnizip/profiler/report_generator"
require "omnizip/optimization_registry"

RSpec.describe Omnizip::Profiler do
  let(:profiler) { described_class.new(profile_name: "test_profile") }

  describe "#initialize" do
    it "creates a profiler with a profile name" do
      expect(profiler.report.profile_name).to eq("test_profile")
    end

    it "is enabled by default" do
      expect(profiler.enabled).to be true
    end

    it "can be created disabled" do
      disabled_profiler = described_class.new(enabled: false)
      expect(disabled_profiler.enabled).to be false
    end
  end

  describe "#register_profiler" do
    it "registers a profiler strategy" do
      method_profiler = Omnizip::Profiler::MethodProfiler.new
      profiler.register_profiler(:method, method_profiler)
      expect(profiler.instance_variable_get(:@profilers)[:method])
        .to eq(method_profiler)
    end
  end

  describe "#profile" do
    let(:method_profiler) { Omnizip::Profiler::MethodProfiler.new }

    before do
      profiler.register_profiler(:method, method_profiler)
    end

    it "profiles a block of code" do
      result = profiler.profile("test_operation") { 2 + 2 }
      expect(result).to be_a(Omnizip::Models::PerformanceResult)
      expect(result.operation_name).to eq("test_operation")
    end

    it "adds result to report" do
      expect do
        profiler.profile("test_operation") { 2 + 2 }
      end.to change { profiler.report.results.size }.by(1)
    end

    it "returns block result when disabled" do
      profiler.disable!
      result = profiler.profile("test_operation") { 42 }
      expect(result).to eq(42)
    end

    it "raises error for unknown profiler type" do
      expect do
        profiler.profile("test_operation", profiler_type: :unknown) { 2 + 2 }
      end.to raise_error(ArgumentError, /Unknown profiler type/)
    end
  end

  describe "#analyze_hot_paths" do
    let(:method_profiler) { Omnizip::Profiler::MethodProfiler.new }

    before do
      profiler.register_profiler(:method, method_profiler)
    end

    it "identifies operations consuming significant time" do
      # Create operations with different execution times
      profiler.profile("fast_op") { sleep 0.01 }
      profiler.profile("slow_op") { sleep 0.1 }

      hot_paths = profiler.analyze_hot_paths(threshold_percentage: 50.0)
      expect(hot_paths).not_to be_empty
      expect(hot_paths.first.operation_name).to eq("slow_op")
    end

    it "adds hot paths to report" do
      profiler.profile("slow_op") { sleep 0.1 }
      profiler.analyze_hot_paths(threshold_percentage: 10.0)
      expect(profiler.report.hot_paths).not_to be_empty
    end
  end

  describe "#identify_bottlenecks" do
    let(:method_profiler) { Omnizip::Profiler::MethodProfiler.new }

    before do
      profiler.register_profiler(:method, method_profiler)
    end

    it "identifies CPU bottlenecks" do
      profiler.profile("slow_operation") { sleep 0.1 }
      bottlenecks = profiler.identify_bottlenecks
      cpu_bottlenecks = bottlenecks.select { |b| b[:type] == :cpu }
      expect(cpu_bottlenecks).not_to be_empty
    end

    it "adds bottlenecks to report" do
      profiler.profile("slow_operation") { sleep 0.1 }
      profiler.identify_bottlenecks
      expect(profiler.report.bottlenecks).not_to be_empty
    end
  end

  describe "#generate_suggestions" do
    let(:method_profiler) { Omnizip::Profiler::MethodProfiler.new }

    before do
      profiler.register_profiler(:method, method_profiler)
    end

    it "generates optimization suggestions" do
      profiler.profile("operation") { sleep 0.1 }
      profiler.analyze_hot_paths(threshold_percentage: 10.0)
      suggestions = profiler.generate_suggestions
      expect(suggestions).to be_an(Array)
      expect(suggestions.first).to be_a(Omnizip::Models::OptimizationSuggestion)
    end

    it "sorts suggestions by priority" do
      profiler.profile("slow_op") { sleep 0.2 }
      profiler.profile("fast_op") { sleep 0.01 }
      profiler.analyze_hot_paths(threshold_percentage: 10.0)
      suggestions = profiler.generate_suggestions
      expect(suggestions.first.related_operations).to include("slow_op")
    end
  end

  describe "#enable! and #disable!" do
    it "enables profiling" do
      profiler.disable!
      profiler.enable!
      expect(profiler.enabled).to be true
    end

    it "disables profiling" do
      profiler.disable!
      expect(profiler.enabled).to be false
    end
  end

  describe "#reset!" do
    let(:method_profiler) { Omnizip::Profiler::MethodProfiler.new }

    before do
      profiler.register_profiler(:method, method_profiler)
    end

    it "resets profiler state" do
      profiler.profile("operation") { 2 + 2 }
      expect(profiler.report.results.size).to eq(1)
      profiler.reset!
      expect(profiler.report.results.size).to eq(0)
    end
  end
end

RSpec.describe Omnizip::Profiler::MethodProfiler do
  let(:profiler) { described_class.new }

  describe "#profile" do
    it "measures execution time" do
      result = profiler.profile("test_operation") { sleep 0.01 }
      expect(result).to be_a(Omnizip::Models::PerformanceResult)
      expect(result.total_time).to be > 0
      expect(result.wall_time).to be > 0
    end

    it "tracks call counts" do
      profiler.profile("operation") { 2 + 2 }
      profiler.profile("operation") { 2 + 2 }
      result = profiler.profile("operation") { 2 + 2 }
      expect(result.call_count).to eq(3)
    end

    it "measures GC runs" do
      result = profiler.profile("operation") do
        1000.times { Array.new(100) }
      end
      expect(result.gc_runs).to be >= 0
    end
  end

  describe "#reset!" do
    it "clears call counts" do
      profiler.profile("operation") { 2 + 2 }
      expect(profiler.call_count("operation")).to eq(1)
      profiler.reset!
      expect(profiler.call_count("operation")).to eq(0)
    end
  end

  describe "#total_calls" do
    it "returns total number of calls across all operations" do
      profiler.profile("op1") { 2 + 2 }
      profiler.profile("op2") { 2 + 2 }
      profiler.profile("op1") { 2 + 2 }
      expect(profiler.total_calls).to eq(3)
    end
  end
end

RSpec.describe Omnizip::Profiler::MemoryProfiler do
  let(:profiler) { described_class.new }

  describe "#profile" do
    it "measures memory allocation" do
      result = profiler.profile("test_operation") do
        Array.new(1000) { "x" * 100 }
      end
      expect(result).to be_a(Omnizip::Models::PerformanceResult)
      expect(result.memory_allocated).to be > 0
      expect(result.object_allocations).to be > 0
    end

    it "tracks call counts" do
      profiler.profile("operation") { Array.new(10) }
      profiler.profile("operation") { Array.new(10) }
      result = profiler.profile("operation") { Array.new(10) }
      expect(result.call_count).to eq(3)
    end
  end
end

RSpec.describe Omnizip::Profiler::ReportGenerator do
  let(:report) do
    Omnizip::Models::ProfileReport.new(profile_name: "test_report")
  end
  let(:generator) { described_class.new(report) }

  before do
    # Add some sample results
    report.add_result(
      Omnizip::Models::PerformanceResult.new(
        operation_name: "test_op",
        total_time: 1.5,
        memory_allocated: 1024 * 1024,
        call_count: 10
      )
    )
  end

  describe "#generate_text_report" do
    it "generates a text report" do
      text_report = generator.generate_text_report
      expect(text_report).to include("PERFORMANCE PROFILING REPORT")
      expect(text_report).to include("test_report")
      expect(text_report).to include("test_op")
    end
  end

  describe "#generate_json_report" do
    it "generates a JSON report" do
      json_report = generator.generate_json_report
      parsed = JSON.parse(json_report)
      expect(parsed["profile_name"]).to eq("test_report")
      expect(parsed["results"]).to be_an(Array)
    end
  end

  describe "#save_to_file" do
    let(:temp_file) { "tmp/test_report.txt" }

    after do
      File.delete(temp_file) if File.exist?(temp_file)
    end

    it "saves text report to file" do
      generator.save_to_file(temp_file, format: :text)
      expect(File.exist?(temp_file)).to be true
      content = File.read(temp_file)
      expect(content).to include("PERFORMANCE PROFILING REPORT")
    end

    it "saves JSON report to file" do
      json_file = "tmp/test_report.json"
      generator.save_to_file(json_file, format: :json)
      expect(File.exist?(json_file)).to be true
      content = JSON.parse(File.read(json_file))
      expect(content["profile_name"]).to eq("test_report")
      File.delete(json_file) if File.exist?(json_file)
    end
  end
end

RSpec.describe Omnizip::OptimizationRegistry do
  after do
    described_class.clear!
  end

  describe ".register" do
    it "registers an optimization strategy" do
      strategy_class = Class.new(described_class::Strategy)
      described_class.register(:test_strategy, strategy_class)
      expect(described_class.registered?(:test_strategy)).to be true
    end
  end

  describe ".get" do
    it "retrieves a registered strategy" do
      strategy_class = Class.new(described_class::Strategy)
      described_class.register(:test_strategy, strategy_class)
      expect(described_class.get(:test_strategy)).to eq(strategy_class)
    end

    it "raises error for unregistered strategy" do
      expect do
        described_class.get(:nonexistent)
      end.to raise_error(Omnizip::Error::OptimizationNotFound)
    end
  end

  describe ".all" do
    it "lists all registered strategies" do
      strategy1 = Class.new(described_class::Strategy)
      strategy2 = Class.new(described_class::Strategy)
      described_class.register(:strategy1, strategy1)
      described_class.register(:strategy2, strategy2)
      expect(described_class.all).to include(:strategy1, :strategy2)
    end
  end

  describe ".clear!" do
    it "clears all registered strategies" do
      strategy_class = Class.new(described_class::Strategy)
      described_class.register(:test_strategy, strategy_class)
      described_class.clear!
      expect(described_class.all).to be_empty
    end
  end
end

RSpec.describe Omnizip::Models::PerformanceResult do
  let(:result) do
    described_class.new(
      operation_name: "test_op",
      total_time: 2.0,
      memory_allocated: 2048,
      call_count: 5
    )
  end

  describe "#throughput_ops_per_second" do
    it "calculates operations per second" do
      expect(result.throughput_ops_per_second).to eq(2.5)
    end
  end

  describe "#average_time_per_operation" do
    it "calculates average time per operation" do
      expect(result.average_time_per_operation).to eq(0.4)
    end
  end

  describe "#memory_per_operation" do
    it "calculates memory per operation" do
      expect(result.memory_per_operation).to eq(409.6)
    end
  end

  describe "#to_h" do
    it "converts to hash" do
      hash = result.to_h
      expect(hash[:operation_name]).to eq("test_op")
      expect(hash[:total_time]).to eq(2.0)
      expect(hash[:throughput_ops_per_second]).to eq(2.5)
    end
  end
end

RSpec.describe Omnizip::Models::OptimizationSuggestion do
  describe "#initialize" do
    it "creates a suggestion with valid parameters" do
      suggestion = described_class.new(
        title: "Test optimization",
        description: "Test description",
        severity: :high,
        category: :memory
      )
      expect(suggestion.title).to eq("Test optimization")
      expect(suggestion.severity).to eq(:high)
    end

    it "validates severity" do
      expect do
        described_class.new(
          title: "Test",
          description: "Test",
          severity: :invalid,
          category: :memory
        )
      end.to raise_error(ArgumentError, /Invalid severity/)
    end

    it "validates category" do
      expect do
        described_class.new(
          title: "Test",
          description: "Test",
          severity: :high,
          category: :invalid
        )
      end.to raise_error(ArgumentError, /Invalid category/)
    end
  end

  describe "#critical?" do
    it "returns true for critical severity" do
      suggestion = described_class.new(
        title: "Test",
        description: "Test",
        severity: :critical,
        category: :memory
      )
      expect(suggestion.critical?).to be true
    end
  end

  describe "#priority_score" do
    it "calculates priority score" do
      suggestion = described_class.new(
        title: "Test",
        description: "Test",
        severity: :high,
        category: :memory,
        impact_estimate: 0.8,
        implementation_effort: 2.0
      )
      expect(suggestion.priority_score).to be > 0
    end
  end
end