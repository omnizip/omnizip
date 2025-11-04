# frozen_string_literal: true

module Omnizip
  module Models
    # Model for parallel processing configuration
    #
    # Stores settings for parallel compression and extraction operations
    # including thread count, queue size, and load balancing strategy.
    #
    # @example Create parallel options
    #   options = Omnizip::Models::ParallelOptions.new
    #   options.threads = 8
    #   options.queue_size = 100
    #   options.strategy = :dynamic
    #
    # @example Use with parallel compression
    #   Omnizip::Parallel.compress_directory('files/', 'backup.zip', options)
    class ParallelOptions
      # @return [Integer] Number of worker threads (default: auto-detect)
      attr_accessor :threads

      # @return [Integer] Maximum size of job queue (default: 1000)
      attr_accessor :queue_size

      # @return [Integer] Chunk size for chunked operations in bytes
      attr_accessor :chunk_size

      # @return [Symbol] Load balancing strategy (:dynamic or :static)
      attr_accessor :strategy

      # @return [Boolean] Enable verbose progress output
      attr_accessor :verbose

      # @return [Integer] Batch size for work queue polling
      attr_accessor :batch_size

      # Initialize parallel options with default values
      def initialize
        @threads = detect_cpu_count
        @queue_size = 1000
        @chunk_size = 64 * 1024 * 1024 # 64MB default
        @strategy = :dynamic
        @verbose = false
        @batch_size = 10
      end

      # Validate options
      #
      # @raise [ArgumentError] if options are invalid
      # @return [Boolean] true if valid
      def validate!
        raise ArgumentError, "threads must be > 0" if threads <= 0
        raise ArgumentError, "queue_size must be > 0" if queue_size <= 0
        raise ArgumentError, "chunk_size must be > 0" if chunk_size <= 0
        raise ArgumentError, "strategy must be :dynamic or :static" unless %i[dynamic static].include?(strategy)
        raise ArgumentError, "batch_size must be > 0" if batch_size <= 0

        true
      end

      # Create a copy of options
      #
      # @return [ParallelOptions] new instance with same values
      def dup
        copy = self.class.new
        copy.threads = threads
        copy.queue_size = queue_size
        copy.chunk_size = chunk_size
        copy.strategy = strategy
        copy.verbose = verbose
        copy.batch_size = batch_size
        copy
      end

      # Convert to hash
      #
      # @return [Hash] options as hash
      def to_h
        {
          threads: threads,
          queue_size: queue_size,
          chunk_size: chunk_size,
          strategy: strategy,
          verbose: verbose,
          batch_size: batch_size,
        }
      end

      private

      # Detect number of available CPU cores
      #
      # @return [Integer] number of CPUs
      def detect_cpu_count
        require "etc"
        Etc.nprocessors
      rescue StandardError
        4 # fallback to 4 threads
      end
    end
  end
end