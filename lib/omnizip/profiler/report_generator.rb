# frozen_string_literal: true

require "json"
require "fileutils"

module Omnizip
  class Profiler
    # Generates formatted profiling reports with optimization recommendations
    class ReportGenerator
      attr_reader :report

      def initialize(report)
        @report = report
      end

      # Generate a human-readable text report
      def generate_text_report
        lines = []
        lines << ("=" * 80)
        lines << "PERFORMANCE PROFILING REPORT"
        lines << ("=" * 80)
        lines << "Profile: #{report.profile_name}"
        lines << "Timestamp: #{report.timestamp}"
        lines << ""

        lines += generate_summary_section
        lines += generate_results_section
        lines += generate_hot_paths_section
        lines += generate_bottlenecks_section

        lines.join("\n")
      end

      # Generate a JSON report
      def generate_json_report
        JSON.pretty_generate(report.to_h)
      end

      # Save report to file
      def save_to_file(filename, format: :text)
        content = case format
                  when :text then generate_text_report
                  when :json then generate_json_report
                  else raise ArgumentError, "Unknown format: #{format}"
                  end

        # Create parent directories if they don't exist
        dir = File.dirname(filename)
        FileUtils.mkdir_p(dir)

        File.write(filename, content)
        puts "Report saved to #{filename}"
      end

      # Print report to console
      def print_report
        puts generate_text_report
      end

      private

      def generate_summary_section
        lines = []
        lines << ("-" * 80)
        lines << "SUMMARY"
        lines << ("-" * 80)
        lines << format("Total Execution Time: %.3fs",
                        report.total_execution_time)
        lines << format("Total Memory Allocated: %s",
                        format_bytes(report.total_memory_allocated))
        lines << format("Total GC Runs: %d", report.total_gc_runs)
        lines << format("Operations Profiled: %d", report.results.size)
        lines << ""
        lines
      end

      def generate_results_section
        return [] if report.results.empty?

        lines = []
        lines << ("-" * 80)
        lines << "DETAILED RESULTS"
        lines << ("-" * 80)
        lines << "Operation                                    Time (s)          Memory      Calls"
        lines << ("-" * 80)

        report.results.sort_by(&:total_time).reverse.each do |result|
          lines << format("%-40s %12.3f %15s %10d",
                          truncate(result.operation_name, 40),
                          result.total_time || 0.0,
                          format_bytes(result.memory_allocated || 0),
                          result.call_count || 0)
        end
        lines << ""
        lines
      end

      def generate_hot_paths_section
        return [] if report.hot_paths.empty?

        lines = []
        lines << ("-" * 80)
        lines << "HOT PATHS (>10% execution time)"
        lines << ("-" * 80)

        report.hot_paths.each do |hot_path|
          lines << format("  %s: %.3fs (%.1f%%)",
                          hot_path[:operation],
                          hot_path[:time],
                          hot_path[:percentage])
        end
        lines << ""
        lines
      end

      def generate_bottlenecks_section
        return [] if report.bottlenecks.empty?

        lines = []
        lines << ("-" * 80)
        lines << "PERFORMANCE BOTTLENECKS"
        lines << ("-" * 80)

        report.bottlenecks.group_by { |b| b[:type] }.each do |type, bottlenecks|
          lines << "\n#{type.to_s.upcase} Bottlenecks:"
          bottlenecks.each do |bottleneck|
            lines << format("  [%s] %s",
                            bottleneck[:severity].to_s.upcase,
                            bottleneck[:operation])

            case type
            when :memory
              lines << format("    Memory: %s",
                              format_bytes(bottleneck[:allocated]))
            when :cpu
              lines << format("    Time: %.3fs", bottleneck[:time])
            when :gc
              lines << format("    GC Pressure: %.2f runs/s",
                              bottleneck[:gc_pressure])
            end
          end
        end
        lines << ""
        lines
      end

      def format_bytes(bytes)
        return "0 B" if bytes.nil? || bytes.zero?

        units = %w[B KB MB GB]
        size = bytes.to_f
        unit_index = 0

        while size >= 1024.0 && unit_index < units.size - 1
          size /= 1024.0
          unit_index += 1
        end

        format("%.2f %s", size, units[unit_index])
      end

      def truncate(string, max_length)
        return string if string.length <= max_length

        "#{string[0...(max_length - 3)]}..."
      end
    end
  end
end
