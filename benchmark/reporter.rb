# frozen_string_literal: true

require "json"

module Benchmark
  # Formats and reports benchmark results
  class Reporter
    def initialize(results)
      @results = results
    end

    def print_summary
      puts "\n#{"=" * 80}"
      puts "OMNIZIP vs 7-ZIP BENCHMARK RESULTS"
      puts "=" * 80

      @results.each do |result|
        print_comparison(result)
      end

      print_overall_summary
    end

    def save_to_file(filename)
      File.write(filename, to_json)
      puts "\nResults saved to #{filename}"
    end

    def to_json(*_args)
      JSON.pretty_generate({
                             timestamp: Time.now.iso8601,
                             results: @results.map(&:to_h)
                           })
    end

    private

    def print_comparison(result)
      puts "\n#{"-" * 80}"
      puts "Test: #{result.test_name}"
      puts "-" * 80

      if result.both_successful?
        print_successful_comparison(result)
      else
        print_failed_comparison(result)
      end
    end

    def print_successful_comparison(result)
      omni = result.omnizip_result
      seven = result.seven_zip_result

      puts "Metric                                 Omnizip           7-Zip"
      puts "-" * 80

      puts format("%-30s %15s %15s",
                  "Input Size",
                  format_bytes(omni.input_size),
                  format_bytes(seven.input_size))

      puts format("%-30s %15s %15s",
                  "Compressed Size",
                  format_bytes(omni.compressed_size),
                  format_bytes(seven.compressed_size))

      puts format("%-30s %15.2f %15.2f",
                  "Compression Ratio",
                  omni.compression_ratio || 0.0,
                  seven.compression_ratio || 0.0)

      puts format("%-30s %15.3fs %15.3fs",
                  "Compression Time",
                  omni.compression_time || 0.0,
                  seven.compression_time || 0.0)

      puts "\n#{"-" * 80}"
      puts "Comparison:"
      puts "-" * 80

      if result.size_difference_bytes
        puts format("  Size difference: %+d bytes (%+.1f%%)",
                    result.size_difference_bytes,
                    result.size_difference_percentage)
      end

      return unless result.compression_speed_ratio

      puts format("  Speed ratio: %.1fx slower",
                  result.compression_speed_ratio)
    end

    def print_failed_comparison(result)
      puts "\nOmnizip:"
      print_result_status(result.omnizip_result)

      puts "\n7-Zip:"
      print_result_status(result.seven_zip_result)
    end

    def print_result_status(result)
      if result.success?
        puts "  Success"
        puts "  Compressed: #{format_bytes(result.compressed_size)}"
        puts "  Time: #{format_time(result.compression_time)}"
      else
        puts "  Failed: #{result.error}"
      end
    end

    def print_overall_summary
      puts "\n#{"=" * 80}"
      puts "OVERALL SUMMARY"
      puts "=" * 80

      successful = @results.select(&:both_successful?)
      total = @results.size

      puts "Successful comparisons: #{successful.size}/#{total}"

      return if successful.empty?

      avg_size_diff = successful.map(&:size_difference_percentage)
                                .compact.sum / successful.size
      avg_speed_ratio = successful.map(&:compression_speed_ratio)
                                  .compact.sum / successful.size

      puts format("\nAverage size difference: %+.1f%%", avg_size_diff)
      puts format("Average speed ratio: %.1fx slower", avg_speed_ratio)
    end

    def format_bytes(bytes)
      return "N/A" if bytes.nil?

      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / (1024.0 * 1024)).round(1)}MB"
      end
    end

    def format_time(seconds)
      return "N/A" if seconds.nil?

      "#{seconds.round(3)}s"
    end
  end
end
