# frozen_string_literal: true

require "benchmark"
require "tempfile"
require "fileutils"
require_relative "models/benchmark_result"
require_relative "models/comparison_result"

module Benchmark
  # Benchmarks compression algorithms against native 7-Zip
  class CompressionBench
    ALGORITHMS = %w[lzma lzma2 ppmd7 bzip2].freeze
    ITERATIONS = 3

    attr_reader :verbose

    def initialize(verbose: false)
      @verbose = verbose
      @seven_zip_available = check_seven_zip_availability
    end

    def seven_zip_available?
      @seven_zip_available
    end

    def benchmark_algorithm(algorithm, input_file, input_type)
      puts "Benchmarking #{algorithm} on #{input_type}..." if verbose

      omnizip_result = benchmark_omnizip(algorithm, input_file, input_type)
      seven_zip_result = if seven_zip_available?
                           benchmark_seven_zip(algorithm, input_file,
                                               input_type)
                         else
                           create_unavailable_result(algorithm, input_file,
                                                     input_type)
                         end

      Models::ComparisonResult.new(
        test_name: "#{algorithm}_#{input_type}",
        omnizip_result: omnizip_result,
        seven_zip_result: seven_zip_result
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

    def benchmark_omnizip(algorithm, input_file, input_type)
      input_size = File.size(input_file)
      compressed_file = create_temp_file(".7z")

      begin
        time = measure_time do
          compress_with_omnizip(algorithm, input_file, compressed_file)
        end

        compressed_size = if File.exist?(compressed_file)
                            File.size(compressed_file)
                          end

        Models::BenchmarkResult.new(
          algorithm: algorithm,
          input_size: input_size,
          input_type: input_type,
          compressed_size: compressed_size,
          compression_time: time
        )
      rescue StandardError => e
        Models::BenchmarkResult.new(
          algorithm: algorithm,
          input_size: input_size,
          input_type: input_type,
          error: e.message
        )
      ensure
        FileUtils.rm_f(compressed_file)
      end
    end

    def benchmark_seven_zip(algorithm, input_file, input_type)
      input_size = File.size(input_file)
      compressed_file = create_temp_file(".7z")

      begin
        time = measure_time do
          compress_with_7z(algorithm, input_file, compressed_file)
        end

        compressed_size = if File.exist?(compressed_file)
                            File.size(compressed_file)
                          end

        Models::BenchmarkResult.new(
          algorithm: algorithm,
          input_size: input_size,
          input_type: input_type,
          compressed_size: compressed_size,
          compression_time: time
        )
      rescue StandardError => e
        Models::BenchmarkResult.new(
          algorithm: algorithm,
          input_size: input_size,
          input_type: input_type,
          error: e.message
        )
      ensure
        FileUtils.rm_f(compressed_file)
      end
    end

    def create_unavailable_result(algorithm, input_file, input_type)
      Models::BenchmarkResult.new(
        algorithm: algorithm,
        input_size: File.size(input_file),
        input_type: input_type,
        error: "7-Zip not available"
      )
    end

    def compress_with_omnizip(algorithm, input_file, output_file)
      require_relative "../lib/omnizip"

      algo_class = case algorithm
                   when "lzma" then Omnizip::Algorithms::LZMA
                   when "lzma2" then Omnizip::Algorithms::LZMA2
                   when "ppmd7" then Omnizip::Algorithms::PPMd7
                   when "bzip2" then Omnizip::Algorithms::BZip2
                   else raise "Unknown algorithm: #{algorithm}"
                   end

      input = File.binread(input_file)
      compressed = algo_class.compress(input)
      File.binwrite(output_file, compressed)
    end

    def compress_with_7z(algorithm, input_file, output_file)
      method_flag = case algorithm
                    when "lzma" then "LZMA"
                    when "lzma2" then "LZMA2"
                    when "ppmd7" then "PPMd"
                    when "bzip2" then "BZip2"
                    else raise "Unknown algorithm: #{algorithm}"
                    end

      cmd = "#{get_7z_command} a -m0=#{method_flag} -mx=5 #{output_file} " \
            "#{input_file} > /dev/null 2>&1"
      success = system(cmd)
      raise "7z compression failed" unless success
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
