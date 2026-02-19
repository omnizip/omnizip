# frozen_string_literal: true

module Omnizip
  module Temp
    # Resource pool for managing reusable temp files
    class TempFilePool
      DEFAULT_POOL_SIZE = 10

      attr_reader :size

      # Create new temp file pool
      # @param size [Integer] Maximum pool size
      def initialize(size: DEFAULT_POOL_SIZE)
        @size = size
        @pool = []
        @mutex = Mutex.new
        @created_count = 0
        @reuse_count = 0
      end

      # Acquire temp file from pool
      # @yield [temp_file] Block called with temp file
      # @return [Object] Block return value
      def acquire(**options)
        temp_file = get_or_create(**options)

        begin
          result = yield temp_file
          release(temp_file)
          result
        rescue StandardError => e
          # Ensure cleanup even on exception
          temp_file.unlink
          raise e
        end
      end

      # Release temp file back to pool or delete if pool is full
      # @param temp_file [TempFile] File to release
      def release(temp_file)
        @mutex.synchronize do
          if @pool.size < @size
            # Return to pool for reuse
            temp_file.rewind
            @pool << temp_file
            @reuse_count += 1
          else
            # Pool full, delete it
            temp_file.unlink
          end
        end
      end

      # Clear all files from pool
      def clear
        @mutex.synchronize do
          @pool.each do |tf|
            tf.unlink
          rescue StandardError
            nil
          end
          @pool.clear
        end
      end

      # Get available file count in pool
      # @return [Integer] Number of available files
      def available_count
        @mutex.synchronize { @pool.size }
      end

      # Get statistics
      # @return [Hash] Pool statistics
      def stats
        @mutex.synchronize do
          {
            pool_size: @size,
            available: @pool.size,
            created: @created_count,
            reused: @reuse_count,
            efficiency: efficiency_ratio,
          }
        end
      end

      private

      def get_or_create(**options)
        @mutex.synchronize do
          if @pool.empty?
            # Create new temp file
            @created_count += 1
            TempFile.new(**options)
          else
            # Reuse from pool (LRU - take from front)
            @pool.shift
          end
        end
      end

      def efficiency_ratio
        total = @created_count + @reuse_count
        return 0.0 if total.zero?

        (@reuse_count.to_f / total * 100).round(2)
      end
    end
  end
end
