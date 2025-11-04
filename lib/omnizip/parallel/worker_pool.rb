# frozen_string_literal: true

require "fractor"

module Omnizip
  module Parallel
    # Worker pool wrapper for Fractor-based parallel processing
    #
    # Manages a pool of Fractor workers for parallel compression/extraction.
    # Handles job distribution, result collection, and graceful shutdown.
    #
    # @example Create and use worker pool
    #   pool = Omnizip::Parallel::WorkerPool.new(
    #     worker_class: CompressionWorker,
    #     num_workers: 4
    #   )
    #   pool.start
    #   pool.submit(work_item)
    #   results = pool.results
    #   pool.shutdown
    class WorkerPool
      # @return [Fractor::Supervisor] underlying Fractor supervisor
      attr_reader :supervisor

      # @return [Array] collected results
      attr_reader :results

      # @return [Array] collected errors
      attr_reader :errors

      # @return [Boolean] whether pool is running
      attr_reader :running

      # Initialize worker pool
      #
      # @param worker_class [Class] Fractor::Worker subclass
      # @param num_workers [Integer] number of worker threads
      # @param continuous [Boolean] continuous mode for long-running tasks
      def initialize(worker_class:, num_workers: nil, continuous: false)
        @worker_class = worker_class
        @num_workers = num_workers || detect_cpu_count
        @continuous = continuous
        @supervisor = nil
        @results = []
        @errors = []
        @running = false
        @result_mutex = Mutex.new
        @work_queue = nil
      end

      # Start the worker pool
      #
      # @return [void]
      def start
        return if @running

        # Create Fractor supervisor with worker pool configuration
        @supervisor = Fractor::Supervisor.new(
          worker_pools: [
            {
              worker_class: @worker_class,
              num_workers: @num_workers,
            },
          ],
          continuous_mode: @continuous,
        )

        # For continuous mode, set up work queue
        if @continuous
          @work_queue = Fractor::WorkQueue.new
          @work_queue.register_with_supervisor(@supervisor)
        end

        @running = true

        # Start supervisor in background thread for continuous mode
        if @continuous
          @supervisor_thread = Thread.new do
            @supervisor.run
          rescue StandardError => e
            @result_mutex.synchronize do
              @errors << { error: e, message: "Supervisor error: #{e.message}" }
            end
          end
        else
          # For batch mode, don't start yet - wait for work items
          @supervisor.start_workers
        end
      end

      # Submit work item to the pool
      #
      # @param work [Fractor::Work] work item to process
      # @return [void]
      def submit(work)
        raise "Worker pool not started" unless @running

        if @continuous
          # In continuous mode, add to work queue
          @work_queue << work
        else
          # In batch mode, add to supervisor
          @supervisor.add_work_item(work)
        end
      end

      # Submit multiple work items
      #
      # @param works [Array<Fractor::Work>] array of work items
      # @return [void]
      def submit_batch(works)
        works.each { |work| submit(work) }
      end

      # Run the pool in batch mode and wait for completion
      #
      # @return [void]
      def run
        raise "Can only run in batch mode" if @continuous
        raise "Worker pool not started" unless @running

        @supervisor.run

        # Collect results
        collect_results
      end

      # Shutdown the worker pool
      #
      # @param timeout [Numeric] timeout in seconds
      # @return [void]
      def shutdown(timeout: 30)
        return unless @running

        if @continuous
          @supervisor.stop
          @supervisor_thread&.join(timeout)
        end

        # Collect final results
        collect_results

        @running = false
      end

      # Get successful results
      #
      # @return [Array] array of successful results
      def successful_results
        @result_mutex.synchronize { @results.dup }
      end

      # Get failed results
      #
      # @return [Array] array of errors
      def failed_results
        @result_mutex.synchronize { @errors.dup }
      end

      # Get pool statistics
      #
      # @return [Hash] statistics hash
      def stats
        return {} unless @supervisor

        {
          workers: @num_workers,
          running: @running,
          continuous: @continuous,
          results: @results.size,
          errors: @errors.size,
          total_processed: @results.size + @errors.size,
        }
      end

      # Check if pool has completed all work
      #
      # @return [Boolean] true if complete
      def complete?
        return false if @continuous
        return false unless @supervisor

        # In batch mode, check if all work is processed
        result_aggregator = @supervisor.results
        result_aggregator && !@supervisor.work_queue.empty?
      end

      private

      # Collect results from supervisor
      #
      # @return [void]
      def collect_results
        return unless @supervisor

        result_aggregator = @supervisor.results
        return unless result_aggregator

        @result_mutex.synchronize do
          # Collect successful results
          result_aggregator.results.each do |work_result|
            @results << work_result
          end

          # Collect errors
          result_aggregator.errors.each do |error_result|
            @errors << error_result
          end
        end
      end

      # Detect number of available CPU cores
      #
      # @return [Integer] number of CPUs
      def detect_cpu_count
        require "etc"
        Etc.nprocessors
      rescue StandardError
        4 # fallback
      end
    end
  end
end