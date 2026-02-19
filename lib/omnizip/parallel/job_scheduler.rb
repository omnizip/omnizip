# frozen_string_literal: true

module Omnizip
  module Parallel
    # Job scheduler for load balancing and work distribution
    #
    # Manages job assignment to workers using different strategies:
    # - Dynamic: Workers pull jobs as they become available (default)
    # - Static: Pre-assign equal chunks to each worker
    #
    # @example Create scheduler with dynamic strategy
    #   scheduler = Omnizip::Parallel::JobScheduler.new(strategy: :dynamic)
    #   scheduler.schedule_jobs(jobs, worker_count: 4)
    #
    # @example Create scheduler with static strategy
    #   scheduler = Omnizip::Parallel::JobScheduler.new(strategy: :static)
    #   assignments = scheduler.schedule_jobs(jobs, worker_count: 4)
    class JobScheduler
      # @return [Symbol] scheduling strategy
      attr_reader :strategy

      # Initialize job scheduler
      #
      # @param strategy [Symbol] :dynamic or :static
      def initialize(strategy: :dynamic)
        @strategy = strategy
        validate_strategy!
      end

      # Schedule jobs for workers
      #
      # @param jobs [Array] array of jobs to schedule
      # @param worker_count [Integer] number of workers
      # @return [Hash, Array] assignments (strategy-dependent)
      def schedule_jobs(jobs, worker_count:)
        case @strategy
        when :dynamic
          schedule_dynamic(jobs, worker_count)
        when :static
          schedule_static(jobs, worker_count)
        end
      end

      # Estimate completion time based on job sizes and worker count
      #
      # @param jobs [Array] array of jobs with :size attribute
      # @param worker_count [Integer] number of workers
      # @param bytes_per_second [Float] processing rate
      # @return [Float] estimated seconds to completion
      def estimate_completion_time(jobs, worker_count:,
bytes_per_second: 10_000_000)
        total_bytes = jobs.sum { |job| job.respond_to?(:size) ? job.size : 0 }
        return 0.0 if total_bytes.zero? || worker_count.zero?

        # Simple estimate: total bytes / (workers * rate)
        total_bytes.to_f / (worker_count * bytes_per_second)
      end

      # Calculate load balance quality metric
      #
      # @param assignments [Hash] worker_id => [jobs] mapping
      # @return [Float] balance score (0.0 = perfect, 1.0 = worst)
      def calculate_load_balance(assignments)
        return 0.0 if assignments.empty?

        # Calculate total size per worker
        worker_sizes = assignments.transform_values do |jobs|
          jobs.sum { |job| job.respond_to?(:size) ? job.size : 1 }
        end

        sizes = worker_sizes.values
        return 0.0 if sizes.empty? || sizes.max.zero?

        # Balance = (max - min) / max
        (sizes.max - sizes.min).to_f / sizes.max
      end

      private

      # Validate scheduling strategy
      #
      # @raise [ArgumentError] if strategy is invalid
      def validate_strategy!
        valid_strategies = %i[dynamic static]
        return if valid_strategies.include?(@strategy)

        raise ArgumentError,
              "Invalid strategy: #{@strategy}. Must be one of: #{valid_strategies.join(', ')}"
      end

      # Dynamic scheduling: jobs pulled from queue as workers become available
      #
      # @param jobs [Array] jobs to schedule
      # @param worker_count [Integer] number of workers
      # @return [Hash] scheduling metadata
      def schedule_dynamic(jobs, worker_count)
        # In dynamic mode, we don't pre-assign jobs
        # Workers pull from shared queue as they complete work
        # Return metadata about the scheduling
        {
          strategy: :dynamic,
          total_jobs: jobs.size,
          worker_count: worker_count,
          estimated_jobs_per_worker: (jobs.size.to_f / worker_count).ceil,
          queue: jobs, # Jobs will be consumed from this queue
        }
      end

      # Static scheduling: pre-assign jobs to workers in balanced chunks
      #
      # @param jobs [Array] jobs to schedule
      # @param worker_count [Integer] number of workers
      # @return [Hash] worker_id => [jobs] mapping
      def schedule_static(jobs, worker_count)
        return {} if jobs.empty? || worker_count.zero?

        # Sort jobs by size (largest first) for better balance
        sorted_jobs = jobs.sort_by do |job|
          -(job.respond_to?(:size) ? job.size : 0)
        end

        # Initialize worker assignments
        assignments = (0...worker_count).to_h { |i| [i, []] }
        worker_loads = Array.new(worker_count, 0)

        # Assign each job to worker with smallest current load
        sorted_jobs.each do |job|
          job_size = job.respond_to?(:size) ? job.size : 1

          # Find worker with minimum load
          min_worker = worker_loads.each_with_index.min_by { |load, _| load }[1]

          # Assign job to this worker
          assignments[min_worker] << job
          worker_loads[min_worker] += job_size
        end

        # Add metadata
        assignments[:metadata] = {
          strategy: :static,
          total_jobs: jobs.size,
          worker_count: worker_count,
          balance_score: calculate_load_balance(assignments.except(:metadata)),
          worker_loads: worker_loads,
        }

        assignments
      end

      # Round-robin assignment (alternative simple strategy)
      #
      # @param jobs [Array] jobs to schedule
      # @param worker_count [Integer] number of workers
      # @return [Hash] worker_id => [jobs] mapping
      def schedule_round_robin(jobs, worker_count)
        return {} if jobs.empty? || worker_count.zero?

        assignments = (0...worker_count).to_h { |i| [i, []] }

        jobs.each_with_index do |job, index|
          worker_id = index % worker_count
          assignments[worker_id] << job
        end

        assignments
      end

      # Size-aware assignment with bin packing
      #
      # @param jobs [Array] jobs to schedule
      # @param worker_count [Integer] number of workers
      # @return [Hash] worker_id => [jobs] mapping
      def schedule_bin_packing(jobs, worker_count)
        return {} if jobs.empty? || worker_count.zero?

        # Sort jobs by size (largest first)
        sorted_jobs = jobs.sort_by do |job|
          -(job.respond_to?(:size) ? job.size : 0)
        end

        # First-fit decreasing bin packing
        bins = Array.new(worker_count) { { jobs: [], total_size: 0 } }

        sorted_jobs.each do |job|
          job_size = job.respond_to?(:size) ? job.size : 1

          # Find bin with minimum total size
          min_bin = bins.min_by { |bin| bin[:total_size] }
          min_bin[:jobs] << job
          min_bin[:total_size] += job_size
        end

        # Convert to standard format
        assignments = {}
        bins.each_with_index do |bin, index|
          assignments[index] = bin[:jobs]
        end

        assignments
      end
    end
  end
end
