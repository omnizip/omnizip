# frozen_string_literal: true

require_relative "test_data"
require_relative "compression_bench"
require_relative "filter_bench"
require_relative "reporter"

module Benchmark
  # Main orchestrator for running all benchmarks
  class BenchmarkSuite
    TEST_SIZES = [1024, 10_240, 102_400].freeze # 1KB, 10KB, 100KB
    DATA_TYPES = %w[text source_code repetitive random].freeze

    attr_reader :verbose, :results

    def initialize(verbose: false, quick: false)
      @verbose = verbose
      @quick = quick
      @test_data = TestData.new
      @compression_bench = CompressionBench.new(verbose: verbose)
      @filter_bench = FilterBench.new(verbose: verbose)
      @results = []
    end

    def run_all
      puts "Starting Omnizip vs 7-Zip benchmark suite..."
      puts "7-Zip available: #{@compression_bench.seven_zip_available?}"

      generate_test_data
      run_compression_benchmarks
      run_filter_benchmarks
      cleanup_test_data

      self
    end

    def run_compression_only
      puts "Running compression benchmarks only..."
      generate_test_data
      run_compression_benchmarks
      cleanup_test_data
      self
    end

    def run_filters_only
      puts "Running filter benchmarks only..."
      generate_test_data
      run_filter_benchmarks
      cleanup_test_data
      self
    end

    def report
      Reporter.new(@results).print_summary
    end

    def save_results(filename)
      Reporter.new(@results).save_to_file(filename)
    end

    private

    def generate_test_data
      puts "\nGenerating test data..." if verbose

      sizes = @quick ? [TEST_SIZES.first] : TEST_SIZES
      types = @quick ? [DATA_TYPES.first] : DATA_TYPES

      sizes.each do |size|
        types.each do |type|
          @test_data.public_send("generate_#{type}", size,
                                 filename: "#{type}_#{size}.dat")
        end
      end
    end

    def run_compression_benchmarks
      puts "\nRunning compression benchmarks..." if verbose

      sizes = @quick ? [TEST_SIZES.first] : TEST_SIZES
      types = @quick ? [DATA_TYPES.first] : DATA_TYPES
      algos = @quick ? ["lzma"] : CompressionBench::ALGORITHMS

      algos.each do |algorithm|
        sizes.each do |size|
          types.each do |type|
            filename = "#{type}_#{size}.dat"
            filepath = File.join(@test_data.data_dir, filename)

            result = @compression_bench.benchmark_algorithm(
              algorithm, filepath, type
            )
            @results << result
          end
        end
      end
    end

    def run_filter_benchmarks
      puts "\nRunning filter benchmarks..." if verbose

      return if @quick

      sizes = [TEST_SIZES[1]]
      types = %w[source_code]

      FilterBench::FILTERS.each do |filter|
        sizes.each do |size|
          types.each do |type|
            filename = "#{type}_#{size}.dat"
            filepath = File.join(@test_data.data_dir, filename)

            result = @filter_bench.benchmark_filter(filter, filepath, type)
            @results << result
          end
        end
      end
    end

    def cleanup_test_data
      puts "\nCleaning up test data..." if verbose
      @test_data.cleanup
    end
  end
end
