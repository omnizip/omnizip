# frozen_string_literal: true

require "fractor"

module Omnizip
  module Parallel
    # Engine owns the Fractor worker-pool dance: build the pool, submit
    # a batch of work, run it to completion, return successful and
    # failed results. Callers (ParallelCompressor, ParallelExtractor,
    # future operations) supply the worker class and the work items;
    # Engine handles the threading.
    #
    # This is the deep module behind the parallel API: the threading
    # shape is identical across every consumer, so it lives here once.
    # Domain-specific concerns (which file to read, which archive to
    # open, what stats to track) stay with the caller.
    class Engine
      # @param worker_class [Class] a +Fractor::Worker+ subclass whose
      #   +#process(work)+ turns one work item into a result.
      # @param threads [Integer] worker count.
      def initialize(worker_class:, threads:)
        @worker_class = worker_class
        @threads = threads
      end

      # Run +work_items+ through the pool and yield each successful
      # +Fractor::WorkResult+ to the caller-supplied block.
      #
      # @param work_items [Array<Fractor::Work>] batch to submit.
      # @yieldparam result [Fractor::WorkResult] a successful result.
      # @return [Array<Fractor::WorkResult>] the failed results, for
      #   the caller to decide how to surface.
      def run(work_items)
        pool = Fractor::WorkerPool.new(
          worker_class: @worker_class,
          num_workers: @threads,
          continuous: false,
        )
        pool.start
        pool.submit_batch(work_items)
        pool.run

        pool.successful_results.each { |r| yield r if block_given? }
        pool.failed_results
      end
    end
  end
end
