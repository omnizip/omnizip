# frozen_string_literal: true

require "benchmark"
require "tempfile"
require "fileutils"
require_relative "models/benchmark_result"
require_relative "models/comparison_result"

module Benchmark
  # Benchmarks filters combined with compression
  class FilterBench
    FILTERS = %w[bcj delta].freeze
    BASE_ALGORITHM = "lzma"
    ITERATIONS = 3

    attr_reader :verbose

    def initialize(verbose: false)
      @verbose = verbose
      @seven_zip_available = check_seven_zip_availability
    end

    def seven_zip_available?
      @seven_zip_available
    end

    def benchmark_filter(filter, input_file, input_type)
      puts "Benchmarking #{filter} filter..." if verbose

      omnizip_result = benchmark_omnizip_with_filter(filter, input_file,
                                                     input_type)
      seven_zip_result = if seven_zip_available?
                           benchmark_7z_with_filter(filter, input_file,
                                                    input_type)
                         else
                           create_unavailable_result(filter, input_file,
                                                     input_type)
                         end

      Models::ComparisonResult.new(
        test_name: "#{filter}_filter_#{input_type}",
        omnizip_result: omnizip_result,
        seven_zip_result: seven_zip_result,
      )
    end

    private

    def check_seven_zip_availability
      system("which 7z > /dev/null 2>&1") ||
        system("which 7za > /dev/null 2>&1")
    end

    def get_7z_command
      @get_7z_command ||= if system("which 7z > /dev/null 2>&1")
                            "7z"
                          elsif system("which 7za > /dev/null 2>&1")
                            "7za"
                          end
    end

    def benchmark_omnizip_with_filter(filter, input_file, input_type)
      input_size = File.size(input_file)
      compressed_file = create_temp_file(".7z")

      begin
        time = measure_time do
          compress_with_filter(filter, input_file, compressed_file)
        end

        compressed_size = if File.exist?(compressed_file)
                            File.size(compressed_file)
                          end

        Models::BenchmarkResult.new(
          algorithm: "#{filter}+#{BASE_ALGORITHM}",
          input_size: input_size,
          input_type: input_type,
          compressed_size: compressed_size,
          compression_time: time,
        )
      rescue StandardError => e
        Models::BenchmarkResult.new(
          algorithm: "#{filter}+#{BASE_ALGORITHM}",
          input_size: input_size,
          input_type: input_type,
          error: e.message,
        )
      ensure
        FileUtils.rm_f(compressed_file)
      end
    end

    def benchmark_7z_with_filter(filter, input_file, input_type)
      input_size = File.size(input_file)
      compressed_file = create_temp_file(".7z")

      begin
        time = measure_time do
          compress_with_7z_filter(filter, input_file, compressed_file)
        end

        compressed_size = if File.exist?(compressed_file)
                            File.size(compressed_file)
                          end

        Models::BenchmarkResult.new(
          algorithm: "#{filter}+#{BASE_ALGORITHM}",
          input_size: input_size,
          input_type: input_type,
          compressed_size: compressed_size,
          compression_time: time,
        )
      rescue StandardError => e
        Models::BenchmarkResult.new(
          algorithm: "#{filter}+#{BASE_ALGORITHM}",
          input_size: input_size,
          input_type: input_type,
          error: e.message,
        )
      ensure
        FileUtils.rm_f(compressed_file)
      end
    end

    def create_unavailable_result(filter, input_file, input_type)
      Models::BenchmarkResult.new(
        algorithm: "#{filter}+#{BASE_ALGORITHM}",
        input_size: File.size(input_file),
        input_type: input_type,
        error: "7-Zip not available",
      )
    end

    def compress_with_filter(filter, input_file, output_file)
      require_relative "../lib/omnizip"

      filter_class = case filter
                     when "bcj" then Omnizip::Filters::BCJx86
                     when "delta" then Omnizip::Filters::Delta
                     else raise "Unknown filter: #{filter}"
                     end

      input = File.binread(input_file)
      filtered = filter_class.encode(input)
      compressed = Omnizip::Algorithms::LZMA.compress(filtered)
      File.binwrite(output_file, compressed)
    end

    def compress_with_7z_filter(filter, input_file, output_file)
      filter_flag = case filter
                    when "bcj" then "BCJ"
                    when "delta" then "Delta"
                    else raise "Unknown filter: #{filter}"
                    end

      cmd = "#{get_7z_command} a -m0=LZMA -mf=#{filter_flag} -mx=5 " \
            "#{output_file} #{input_file} > /dev/null 2>&1"
      success = system(cmd)
      raise "7z compression with filter failed" unless success
    end

    def measure_time(&block)
      times = []
      ITERATIONS.times do
        time = ::Benchmark.realtime(&block)
        times << time
      end
      times.sum / times.size
    end

    def create_temp_file(extension)
      temp = Tempfile.new(["benchmark", extension])
      path = temp.path
      temp.close
      temp.unlink
      path
    end
  end
end
