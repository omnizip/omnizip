# frozen_string_literal: true

module Omnizip
  module Parallel
    # Thread-safe job queue for parallel compression/extraction
    #
    # Manages a queue of compression or extraction jobs with priority support.
    # Jobs are ordered by priority (large files first for better load balancing).
    #
    # @example Create and use job queue
    #   queue = Omnizip::Parallel::JobQueue.new(max_size: 100)
    #   queue.push(file: 'large.dat', size: 1_000_000, priority: :high)
    #   job = queue.pop
    #
    # @example Size-based priority
    #   queue.push_with_size(file: 'file.txt', size: 1024)
    class JobQueue
      # Job structure for queue items
      Job = Struct.new(:file, :data, :size, :priority, :metadata,
                       keyword_init: true) do
        def <=>(other)
          # Higher priority first, then larger files first
          priority_order = { high: 0, normal: 1, low: 2 }
          priority_cmp = (priority_order[priority] || 1) <=> (priority_order[other.priority] || 1)
          return priority_cmp unless priority_cmp.zero?

          # If same priority, larger files first
          -(size <=> other.size)
        end
      end

      # @return [Integer] maximum queue size
      attr_reader :max_size

      # @return [Integer] current queue size
      attr_reader :size

      # Initialize job queue
      #
      # @param max_size [Integer] maximum number of jobs in queue
      def initialize(max_size: 1000)
        @max_size = max_size
        @queue = []
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @closed = false
        @size = 0
      end

      # Push a job onto the queue
      #
      # @param file [String] file path
      # @param data [Object] job data
      # @param size [Integer] file size in bytes
      # @param priority [Symbol] job priority (:high, :normal, :low)
      # @param metadata [Hash] additional metadata
      # @raise [ClosedQueueError] if queue is closed
      # @return [Job] the created job
      def push(file:, data: nil, size: 0, priority: :normal, metadata: {})
        @mutex.synchronize do
          raise ClosedQueueError, "Queue is closed" if @closed

          # Wait if queue is full
          @cond.wait(@mutex) while @size >= @max_size && !@closed

          raise ClosedQueueError, "Queue is closed" if @closed

          job = Job.new(
            file: file,
            data: data,
            size: size,
            priority: priority,
            metadata: metadata,
          )

          @queue << job
          @size += 1

          # Keep queue sorted by priority
          @queue.sort!

          @cond.signal
          job
        end
      end

      # Push a job with automatic priority based on file size
      #
      # @param file [String] file path
      # @param size [Integer] file size in bytes
      # @param data [Object] job data
      # @param metadata [Hash] additional metadata
      # @return [Job] the created job
      def push_with_size(file:, size:, data: nil, metadata: {})
        # Determine priority based on size
        # Large files (>10MB) get high priority for better load balancing
        priority = if size > 10 * 1024 * 1024
                     :high
                   elsif size > 1024 * 1024
                     :normal
                   else
                     :low
                   end

        push(file: file, data: data, size: size, priority: priority,
             metadata: metadata)
      end

      # Pop a job from the queue
      #
      # @param timeout [Numeric, nil] timeout in seconds, nil for no timeout
      # @return [Job, nil] job or nil if timeout or closed
      def pop(timeout: nil)
        @mutex.synchronize do
          if timeout
            deadline = Time.now + timeout
            while @queue.empty? && !@closed
              remaining = deadline - Time.now
              return nil if remaining <= 0

              @cond.wait(@mutex, remaining)
            end
          else
            @cond.wait(@mutex) while @queue.empty? && !@closed
          end

          return nil if @queue.empty?

          job = @queue.shift
          @size -= 1
          @cond.signal # Signal waiting pushers
          job
        end
      end

      # Pop multiple jobs in batch
      #
      # @param count [Integer] maximum number of jobs to pop
      # @param timeout [Numeric, nil] timeout in seconds
      # @return [Array<Job>] array of jobs (may be empty)
      def pop_batch(count, timeout: nil)
        jobs = []
        count.times do
          job = pop(timeout: timeout)
          break unless job

          jobs << job
        end
        jobs
      end

      # Check if queue is empty
      #
      # @return [Boolean] true if empty
      def empty?
        @mutex.synchronize { @queue.empty? }
      end

      # Check if queue is closed
      #
      # @return [Boolean] true if closed
      def closed?
        @mutex.synchronize { @closed }
      end

      # Close the queue
      #
      # No more jobs can be pushed after closing.
      # Pending pops will return nil.
      def close
        @mutex.synchronize do
          @closed = true
          @cond.broadcast # Wake up all waiting threads
        end
      end

      # Clear all jobs from queue
      #
      # @return [Integer] number of jobs cleared
      def clear
        @mutex.synchronize do
          count = @queue.size
          @queue.clear
          @size = 0
          @cond.broadcast
          count
        end
      end

      # Get queue statistics
      #
      # @return [Hash] statistics hash
      def stats
        @mutex.synchronize do
          {
            size: @size,
            max_size: @max_size,
            closed: @closed,
            utilization: @max_size.zero? ? 0.0 : @size.to_f / @max_size,
            priority_counts: @queue.group_by(&:priority).transform_values(&:count),
          }
        end
      end
    end

    # Exception raised when trying to push to a closed queue
    class ClosedQueueError < StandardError; end
  end
end
