# frozen_string_literal: true

require_relative "../parity"

module Omnizip
  module Commands
    # Command to create PAR2 parity files
    class ParityCreateCommand
      # @return [Array<String>] Files to protect
      attr_reader :files

      # @return [Hash] Command options
      attr_reader :options

      # Initialize command
      #
      # @param files [Array<String>] Files or patterns to protect
      # @param options [Hash] Command options
      def initialize(files, options = {})
        @files = files
        @options = default_options.merge(options)
      end

      # Execute command
      #
      # @return [Integer] Exit code (0 for success)
      def run
        validate_inputs!

        progress = create_progress_callback if @options[:verbose]

        created_files = []
        @files.each do |file_pattern|
          par2_files = Parity.create(
            file_pattern,
            redundancy: @options[:redundancy],
            block_size: @options[:block_size],
            output_dir: @options[:output_dir],
            progress: progress
          )

          created_files.concat(par2_files)
        end

        report_success(created_files)
        0
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
          redundancy: 5,
          block_size: Parity::Par2Creator::DEFAULT_BLOCK_SIZE,
          output_dir: nil,
          verbose: false
        }
      end

      # Validate command inputs
      #
      # @raise [ArgumentError] if inputs invalid
      def validate_inputs!
        raise ArgumentError, "No files specified" if @files.empty?

        unless @options[:redundancy].between?(0, 100)
          raise ArgumentError, "Redundancy must be 0-100%"
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

      # Report successful creation
      #
      # @param files [Array<String>] Created files
      def report_success(files)
        puts "\n✓ Created #{files.size} PAR2 file(s):"
        files.each do |file|
          size = File.size(file)
          puts "  - #{File.basename(file)} (#{format_size(size)})"
        end
        puts "\nRedundancy: #{@options[:redundancy]}%"
        puts "Block size: #{format_size(@options[:block_size])}"
      end

      # Report error
      #
      # @param error [Exception] Error that occurred
      def report_error(error)
        puts "\n✗ Failed to create PAR2 files:"
        puts "  #{error.message}"
      end

      # Format byte size for display
      #
      # @param bytes [Integer] Size in bytes
      # @return [String] Formatted size
      def format_size(bytes)
        if bytes < 1024
          "#{bytes} B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(1)} MB"
        end
      end
    end
  end
end