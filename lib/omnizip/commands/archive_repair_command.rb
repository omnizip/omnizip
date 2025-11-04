# frozen_string_literal: true

module Omnizip
  module Commands
    # Archive repair command
    class ArchiveRepairCommand
      attr_reader :options

      # Initialize command
      #
      # @param options [Hash] Command options
      def initialize(options = {})
        @options = options
      end

      # Run repair
      #
      # @param input_path [String] Path to corrupted archive
      # @param output_path [String] Path for repaired archive
      def run(input_path, output_path)
        require_relative "../formats/rar"

        raise "Archive not found: #{input_path}" unless File.exist?(input_path)

        # Detect format
        format = detect_format(input_path)

        case format
        when :rar
          repair_rar(input_path, output_path)
        else
          puts "Repair not supported for #{format} archives"
          exit 1
        end
      end

      private

      # Detect archive format
      #
      # @param path [String] Archive path
      # @return [Symbol] Format
      def detect_format(path)
        ext = File.extname(path).downcase
        case ext
        when ".rar", ".r00", ".r01"
          :rar
        when ".zip"
          :zip
        when ".7z"
          :seven_zip
        else
          :unknown
        end
      end

      # Repair RAR archive
      #
      # @param input_path [String] Path to corrupted archive
      # @param output_path [String] Path for repaired archive
      def repair_rar(input_path, output_path)
        puts "Repairing #{input_path}..." if @options[:verbose]

        repair_options = {
          use_external_rev: !@options[:no_external_rev],
          verify_repaired: !@options[:no_verify],
          verbose: @options[:verbose]
        }

        result = Omnizip::Formats::Rar.repair(
          input_path,
          output_path,
          repair_options
        )

        display_repair_result(input_path, output_path, result)

        exit 1 unless result.success?
      end

      # Display repair results
      #
      # @param input_path [String] Input archive path
      # @param output_path [String] Output archive path
      # @param result [ArchiveRepairer::RepairResult] Repair results
      def display_repair_result(input_path, output_path, result)
        puts "\nRepair Results:"
        puts "Input: #{input_path}"
        puts "Output: #{output_path}"

        if result.success?
          puts "\nStatus: SUCCESS"
          puts "Repaired files: #{result.repaired_files.size}"
          puts "Repaired blocks: #{result.repaired_blocks.size}"

          if @options[:verbose] && result.repaired_files.any?
            puts "\nRepaired:"
            result.repaired_files.each do |filename|
              puts "  ✓ #{filename}"
            end
          end
        else
          puts "\nStatus: FAILED"

          if result.repaired_files.any?
            puts "Partially repaired: #{result.repaired_files.size} files"
          end

          if result.unrepaired_files.any?
            puts "Unrepaired: #{result.unrepaired_files.size} files"

            if @options[:verbose]
              result.unrepaired_files.each do |filename|
                puts "  ✗ #{filename}"
              end
            end
          end

          if result.errors.any?
            puts "\nErrors:"
            result.errors.each do |error|
              puts "  - #{error}"
            end
          end
        end

        puts "\n#{result.summary}"
      end
    end
  end
end
