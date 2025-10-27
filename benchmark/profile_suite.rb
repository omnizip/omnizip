# frozen_string_literal: true

require "stringio"
require_relative "../lib/omnizip"
require_relative "../lib/omnizip/profiler"
require_relative "../lib/omnizip/profiler/method_profiler"
require_relative "../lib/omnizip/profiler/memory_profiler"
require_relative "../lib/omnizip/profiler/report_generator"
require_relative "test_data"

module Benchmark
  # Profiling suite for performance analysis of compression algorithms
  class ProfileSuite
    attr_reader :profiler, :verbose

    def initialize(verbose: false)
      @verbose = verbose
      @profiler = Omnizip::Profiler.new(profile_name: "compression_profile")
      @test_data = TestData.new

      # Register profiler strategies
      @profiler.register_profiler(:method,
                                   Omnizip::Profiler::MethodProfiler.new)
      @profiler.register_profiler(:memory,
                                   Omnizip::Profiler::MemoryProfiler.new)
    end

    def run_all
      puts "Starting performance profiling suite..." if verbose

      generate_test_data
      profile_lzma_encoding
      profile_lzma_decoding
      profile_range_coder
      profile_bwt_transform
      cleanup_test_data

      analyze_results
      self
    end

    def profile_lzma_encoding
      puts "\nProfiling LZMA encoding..." if verbose

      test_file = File.join(@test_data.data_dir, "text_10240.dat")
      data = File.binread(test_file)

      @profiler.profile("LZMA::encode", profiler_type: :method) do
        output = StringIO.new
        encoder = Omnizip::Algorithms::LZMA::Encoder.new(output)
        encoder.encode_stream(data)
      end
    end

    def profile_lzma_decoding
      puts "Profiling LZMA decoding..." if verbose

      test_file = File.join(@test_data.data_dir, "text_10240.dat")
      data = File.binread(test_file)

      # Encode data first
      encoded_output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::Encoder.new(encoded_output)
      encoder.encode_stream(data)
      encoded = encoded_output.string

      @profiler.profile("LZMA::decode", profiler_type: :method) do
        input = StringIO.new(encoded)
        decoder = Omnizip::Algorithms::LZMA::Decoder.new(input)
        decoder.decode_stream
      end
    end

    def profile_range_coder
      puts "Profiling Range Coder..." if verbose

      data = Array.new(1000) { rand(256) }

      @profiler.profile("RangeCoder::encode", profiler_type: :method) do
        output = StringIO.new
        encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)
        data.each { |byte| encoder.encode_direct_bits(byte, 8) }
        encoder.flush
      end
    end

    def profile_bwt_transform
      puts "Profiling BWT transform..." if verbose

      test_file = File.join(@test_data.data_dir, "text_10240.dat")
      data = File.binread(test_file)

      @profiler.profile("BWT::encode", profiler_type: :method) do
        bwt = Omnizip::Algorithms::BZip2::Bwt.new
        bwt.encode(data)
      end
    end

    def analyze_results
      puts "\nAnalyzing performance results..." if verbose

      @profiler.analyze_hot_paths(threshold_percentage: 15.0)
      @profiler.identify_bottlenecks

      generate_report
      generate_suggestions
    end

    def generate_report
      generator = Omnizip::Profiler::ReportGenerator.new(@profiler.report)

      if verbose
        puts "\n"
        generator.print_report
      end

      generator
    end

    def generate_suggestions
      suggestions = @profiler.generate_suggestions

      return if suggestions.empty?

      puts "\n#{"=" * 80}"
      puts "OPTIMIZATION SUGGESTIONS"
      puts "=" * 80

      suggestions.take(5).each_with_index do |suggestion, index|
        puts "\n#{index + 1}. [#{suggestion.severity.to_s.upcase}] " \
             "#{suggestion.title}"
        puts "   #{suggestion.description}"
        puts "   Category: #{suggestion.category}"
        puts "   Priority Score: #{suggestion.priority_score.round(2)}"
      end

      suggestions
    end

    def save_report(filename, format: :text)
      generator = Omnizip::Profiler::ReportGenerator.new(@profiler.report)
      generator.save_to_file(filename, format: format)
    end

    private

    def generate_test_data
      puts "\nGenerating test data..." if verbose

      @test_data.generate_text(10_240, filename: "text_10240.dat")
      @test_data.generate_repetitive(10_240, filename: "repetitive_10240.dat")
    end

    def cleanup_test_data
      puts "\nCleaning up test data..." if verbose
      @test_data.cleanup
    end
  end
end

# Run profiling if executed directly
if __FILE__ == $PROGRAM_NAME
  suite = Benchmark::ProfileSuite.new(verbose: true)
  suite.run_all
  suite.save_report("profile_report.txt", format: :text)
  suite.save_report("profile_report.json", format: :json)
end