# frozen_string_literal: true

require_relative "../parity"

module Omnizip
  module Commands
    # Command to repair files using PAR2
    class ParityRepairCommand
      # @return [String] PAR2 file path
      attr_reader :par2_file

      # @return [Hash] Command options
      attr_reader :options

      # Initialize command
      #
      # @param par2_file [String] Path to .par2 index file
      # @param options [Hash] Command options
      def initialize(par2_file, options = {})
        @par2_file = par2_file
        @options = default_options.merge(options)
      end

      # Execute command
      #
      # @return [Integer] Exit code (0 for success)
      def run
        validate_inputs!

        puts "Repairing files with PAR2: #{File.basename(@par2_file)}"
        puts

        progress = create_progress_callback if @options[:verbose]

        result = Parity.repair(
          @par2_file,
          output_dir: @options[:output_dir],
          progress: progress
        )

        display_results(result)

        result.success? ? 0 : 1
      rescue => e
        report_error(e)
        1
      end

      private

      # Default command options
      #
      # @return [Hash] Default options
      def default_options
        {
          output_dir: nil,
          verbose: false
        }
      end

      # Validate command inputs
      #
      # @raise [ArgumentError] if inputs invalid
      def validate_inputs!
        unless File.exist?(@par2_file)
          raise ArgumentError, "PAR2 file not found: #{@par2_file}"
        end
      end

      # Create progress callback
      #
      # @return [Proc] Progress callback
      def create_progress_callback
        ->(percent, message) do
          puts "[#{percent.to_s.rjust(3)}%] #{message}"
        end
      end

      # Display repair results
      #
      # @param result [Omnizip::Parity::Par2Repairer::RepairResult]
      def display_results(result)
        if result.success?
          puts "✓ Repair successful"
          puts

          if result.recovered_files.any?
            puts "Recovered files (#{result.recovered_files.size}):"
            result.recovered_files.each do |file|
              puts "  - #{file}"
            end
          else
            puts "No repairs needed - all files were intact"
          end

          puts
          puts "Recovered blocks: #{result.recovered_blocks}"
        else
          puts "✗ Repair failed"
          puts
          puts "Error: #{result.error_message}"
          puts

          if result.unrecoverable.any?
            puts "Unrecoverable files (#{result.unrecoverable.size}):"
            result.unrecoverable.each do |file|
              puts "  - #{file}"
            end
          end
        end
      end

      # Report error
      #
      # @param error [Exception] Error that occurred
      def report_error(error)
        puts "\n✗ Repair failed:"
        puts "  #{error.message}"
      end
    end
  end
end