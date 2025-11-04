# frozen_string_literal: true

require_relative "parallel/job_queue"
require_relative "parallel/job_scheduler"
require_relative "parallel/worker_pool"
require_relative "parallel/parallel_compressor"
require_relative "parallel/parallel_extractor"

module Omnizip
  # Parallel processing module for multi-threaded compression/extraction
  #
  # Leverages Fractor for parallel processing to utilize multi-core CPUs.
  # Provides high-level APIs for parallel compression and extraction operations.
  #
  # @example Auto-detect CPU count and compress in parallel
  #   Omnizip::Parallel.compress_directory('files/', 'backup.zip')
  #
  # @example Custom thread count
  #   Omnizip::Parallel.compress_directory('files/', 'backup.zip', threads: 8)
  #
  # @example Parallel extraction
  #   Omnizip::Parallel.extract_archive('large.zip', 'output/', threads: 4)
  #
  # @example Configure globally
  #   Omnizip::Parallel.configure do |config|
  #     config.default_threads = 8
  #     config.queue_size = 100
  #     config.load_balancing = :dynamic
  #   end
  module Parallel
    class << self
      # Global configuration
      attr_accessor :config

      # Configure parallel processing globally
      #
      # @yield [config] Configuration block
      # @yieldparam config [Omnizip::Models::ParallelOptions] configuration object
      # @return [void]
      #
      # @example
      #   Omnizip::Parallel.configure do |config|
      #     config.threads = 8
      #     config.queue_size = 100
      #     config.strategy = :dynamic
      #   end
      def configure
        @config ||= Omnizip::Models::ParallelOptions.new
        yield @config if block_given?
        @config.validate!
        @config
      end

      # Compress directory in parallel
      #
      # @param dir [String] directory path
      # @param output [String] output archive path
      # @param options [Hash] compression options
      # @option options [Integer] :threads number of threads
      # @option options [Symbol] :compression compression method
      # @option options [Integer] :level compression level
      # @option options [Boolean] :recursive include subdirectories
      # @option options [Proc] :progress progress callback
      # @return [String] path to created archive
      #
      # @example
      #   Omnizip::Parallel.compress_directory('files/', 'backup.zip')
      #   Omnizip::Parallel.compress_directory('files/', 'backup.zip', threads: 8)
      def compress_directory(dir, output, **options)
        threads = options.delete(:threads) || @config&.threads

        compressor = ParallelCompressor.new(@config, threads: threads)
        result = compressor.compress(dir, output, **options)

        # Print stats if verbose
        if options[:verbose] || @config&.verbose
          stats = compressor.statistics
          print_stats("Compression", stats)
        end

        result
      end

      # Extract archive in parallel
      #
      # @param archive [String] archive path
      # @param dest [String] destination directory
      # @param options [Hash] extraction options
      # @option options [Integer] :threads number of threads
      # @option options [Boolean] :overwrite overwrite existing files
      # @option options [Proc] :progress progress callback
      # @return [Array<String>] extracted file paths
      #
      # @example
      #   Omnizip::Parallel.extract_archive('large.zip', 'output/')
      #   Omnizip::Parallel.extract_archive('large.zip', 'output/', threads: 4)
      def extract_archive(archive, dest, **options)
        threads = options.delete(:threads) || @config&.threads

        extractor = ParallelExtractor.new(@config, threads: threads)
        result = extractor.extract(archive, dest, **options)

        # Print stats if verbose
        if options[:verbose] || @config&.verbose
          stats = extractor.statistics
          print_stats("Extraction", stats)
        end

        result
      end

      # Get default configuration
      #
      # @return [Omnizip::Models::ParallelOptions] configuration
      def default_config
        @config ||= Omnizip::Models::ParallelOptions.new
      end

      # Reset configuration to defaults
      #
      # @return [void]
      def reset_config
        @config = Omnizip::Models::ParallelOptions.new
      end

      private

      # Print statistics
      #
      # @param operation [String] operation name
      # @param stats [Hash] statistics hash
      def print_stats(operation, stats)
        puts "\n=== #{operation} Statistics ==="
        puts "Files processed: #{stats[:files_processed] || stats[:files_extracted] || 0}"
        puts "Duration: #{'%.2f' % stats[:duration]}s"
        puts "Throughput: #{'%.2f' % stats[:throughput_mbps]} MB/s"

        if stats[:compression_ratio]
          puts "Compression ratio: #{'%.2f' % stats[:compression_ratio]}%"
        end

        puts "================================\n"
      end
    end

    # Initialize default configuration
    configure {}
  end
end