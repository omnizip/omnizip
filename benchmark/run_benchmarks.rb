#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "benchmark_suite"

# Parse command-line options
options = {
  verbose: false,
  quick: false,
  mode: :all,
  output: nil
}

ARGV.each do |arg|
  case arg
  when "--verbose", "-v"
    options[:verbose] = true
  when "--quick", "-q"
    options[:quick] = true
  when "--compression-only"
    options[:mode] = :compression
  when "--filters-only"
    options[:mode] = :filters
  when /--output=(.+)/
    options[:output] = Regexp.last_match(1)
  when "--help", "-h"
    puts <<~HELP
      Usage: ruby benchmark/run_benchmarks.rb [OPTIONS]

      Options:
        -v, --verbose          Enable verbose output
        -q, --quick            Run quick benchmarks (1 size, 1 type)
        --compression-only     Run only compression benchmarks
        --filters-only         Run only filter benchmarks
        --output=FILE          Save results to JSON file
        -h, --help             Show this help message

      Examples:
        ruby benchmark/run_benchmarks.rb
        ruby benchmark/run_benchmarks.rb --quick --verbose
        ruby benchmark/run_benchmarks.rb --output=results.json
    HELP
    exit 0
  end
end

# Run benchmarks
suite = Benchmark::BenchmarkSuite.new(
  verbose: options[:verbose],
  quick: options[:quick]
)

case options[:mode]
when :compression
  suite.run_compression_only
when :filters
  suite.run_filters_only
else
  suite.run_all
end

# Display results
suite.report

# Save results if requested
suite.save_results(options[:output]) if options[:output]
