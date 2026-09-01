# frozen_string: true

module Omnizip
  module Parallel
    # Bounded thread pool for library work.
    #
    # Unlike the Fractor pool, threads share the VM state — Ractor
    # workers cannot trigger Omnizip's autoloads or touch Proc-holding
    # codec constants on Ruby <= 3.3 ("require by autoload on
    # non-main Ractor is not supported"). Decompression itself still
    # parallelizes: the zlib/bzip2 C extensions release the GVL.
    class ThreadPool
      # @return [Integer] number of worker threads
      attr_reader :size

      # Initialize the pool
      #
      # @param size [Integer] worker thread count (at least 1)
      def initialize(size:)
        @size = [size.to_i, 1].max
      end

      # Run +block+ for every item, at most +size+ at a time, and
      # return a pair of parallel arrays: results (nil where an item
      # raised) and errors (nil where it succeeded). Item order is
      # preserved in both arrays.
      #
      # @param items [Array] work items
      # @yieldparam item [Object] one work item
      # @return [Array<Array, Array>]
      def map(items)
        results = Array.new(items.size)
        errors = Array.new(items.size)
        queue = Queue.new
        items.each_with_index { |item, index| queue << [item, index] }

        threads = Array.new(@size) do
          Thread.new do
            loop do
              begin
                item, index = queue.pop(true)
              rescue ThreadError
                break
              end

              begin
                results[index] = yield(item)
              rescue StandardError => e
                errors[index] = e
              end
            end
          end
        end
        threads.each(&:join)

        [results, errors]
      end
    end
  end
end
