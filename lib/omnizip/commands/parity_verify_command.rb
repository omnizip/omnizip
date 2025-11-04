# frozen_string_literal: true

require_relative "../parity"

module Omnizip
  module Commands
    # Command to verify files using PAR2
    class ParityVerifyCommand
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
      # @return [Integer] Exit code (0 if all OK, 1 if damage, 2 if error)
      def run
        validate_inputs!

        puts "Verifying files with PAR2: #{File.basename(@par2_file)}"
        puts

        result = Parity.verify(@par2_file)

        display_results(result)

        # Exit code based on results
        if result.all_ok?
          0
        elsif result.repairable?
          1 # Damage but repairable
        else
          2 # Damage not repairable
        end
      rescue => e
        report_error(e)
        2
      end

      private

      # Default command options
      #
      # @return [Hash] Default options
      def default_options
        {
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

      # Display verification results
      #
      # @param result [Omnizip::Parity::Par2Verifier::VerificationResult]
      def display_results(result)
        if result.all_ok?
          puts "✓ All files verified successfully"
          puts
          puts "Total blocks: #{result.total_blocks}"
          puts "Recovery blocks available: #{result.recovery_blocks}"
        else
          puts "✗ File corruption detected"
          puts

          if result.damaged_files.any?
            puts "Damaged files (#{result.damaged_files.size}):"
            result.damaged_files.each do |file|
              puts "  - #{file}"
            end
            puts
          end

          if result.missing_files.any?
            puts "Missing files (#{result.missing_files.size}):"
            result.missing_files.each do |file|
              puts "  - #{file}"
            end
            puts
          end

          puts "Damaged blocks: #{result.damaged_blocks.size}"
          puts "Total blocks: #{result.total_blocks}"
          puts "Recovery blocks available: #{result.recovery_blocks}"
          puts

          if result.repairable?
            puts "✓ Damage is repairable"
            puts "  Run repair command to fix files:"
            puts "  omnizip parity repair #{@par2_file}"
          else
            puts "✗ Damage exceeds recovery capacity"
            puts "  Cannot repair: insufficient recovery blocks"
          end
        end
      end

      # Report error
      #
      # @param error [Exception] Error that occurred
      def report_error(error)
        puts "\n✗ Verification failed:"
        puts "  #{error.message}"
      end
    end
  end
end