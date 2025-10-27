# frozen_string_literal: true

require "tempfile"

module Omnizip
  module Chunked
    # Manage memory usage and enforce limits during chunked operations
    class MemoryManager
      DEFAULT_MAX_MEMORY = 256 * 1024 * 1024 # 256MB

      attr_reader :current_usage, :max_memory

      # Initialize memory manager
      # @param options [Hash] Manager options
      # @option options [Integer] :max Maximum memory in bytes
      # @option options [String] :temp_dir Temporary directory for spill files
      # @option options [Symbol] :strategy Spill strategy (:disk or :error)
      def initialize(max: DEFAULT_MAX_MEMORY, temp_dir: nil, strategy: :disk)
        @max_memory = max
        @current_usage = 0
        @buffers = {} # buffer => size mapping
        @temp_files = []
        @temp_dir = temp_dir
        @strategy = strategy
      end

      # Allocate memory or spill to disk
      # @param size [Integer] Size to allocate in bytes
      # @return [String, Tempfile] Buffer or temp file
      def allocate(size)
        if can_allocate_in_memory?(size)
          allocate_buffer(size)
        else
          handle_overflow(size)
        end
      end

      # Release allocated memory or temp file
      # @param buffer [String, Tempfile] Buffer to release
      # @return [Integer] Bytes released
      def release(buffer)
        case buffer
        when String
          release_buffer(buffer)
        when Tempfile, File
          release_temp_file(buffer)
        else
          0
        end
      end

      # Get available memory
      # @return [Integer] Available memory in bytes
      def available
        [@max_memory - @current_usage, 0].max
      end

      # Check if over memory limit
      # @return [Boolean] True if over limit
      def over_limit?
        @current_usage > @max_memory
      end

      # Get memory usage ratio
      # @return [Float] Usage from 0.0 to 1.0
      def usage_ratio
        return 0.0 if @max_memory.zero?

        @current_usage.to_f / @max_memory
      end

      # Cleanup all resources
      # @return [self]
      def cleanup
        @buffers.clear
        @temp_files.each do |tf|
          begin
            tf.close
          rescue StandardError
            nil
          end
          begin
            tf.unlink
          rescue StandardError
            nil
          end
        end
        @temp_files.clear
        @current_usage = 0
        self
      end

      # Execute block with automatic cleanup
      # @yield [manager] Block to execute with manager
      # @return [Object] Block result
      def self.with_manager(**options)
        manager = new(**options)
        begin
          yield manager
        ensure
          manager.cleanup
        end
      end

      # Spill buffer to disk
      # @param buffer [String] Buffer data to spill
      # @return [Tempfile] Temporary file
      def spill_to_disk(buffer = nil)
        tf = create_temp_file
        tf.write(buffer) if buffer
        tf.rewind
        @temp_files << tf
        tf
      end

      private

      # Check if size can be allocated in memory
      def can_allocate_in_memory?(size)
        @current_usage + size <= @max_memory
      end

      # Allocate in-memory buffer
      def allocate_buffer(size)
        buffer = String.new(capacity: size, encoding: Encoding::BINARY)
        @buffers[buffer] = size
        @current_usage += size
        buffer
      end

      # Release in-memory buffer
      def release_buffer(buffer)
        size = @buffers.delete(buffer)
        if size
          @current_usage -= size
          size
        else
          0
        end
      end

      # Release temp file
      def release_temp_file(file)
        if @temp_files.delete(file)
          size = begin
            file.size
          rescue StandardError
            0
          end
          begin
            file.close
          rescue StandardError
            nil
          end
          begin
            file.unlink
          rescue StandardError
            nil
          end
          size
        else
          0
        end
      end

      # Handle memory overflow based on strategy
      def handle_overflow(size)
        case @strategy
        when :disk
          spill_to_disk
        when :error
          message = "Memory limit exceeded: " \
                    "#{@current_usage + size} > #{@max_memory}"
          raise MemoryError, message
        else
          raise ArgumentError, "Unknown spill strategy: #{@strategy}"
        end
      end

      # Create temporary file
      def create_temp_file
        Tempfile.new(
          ["omnizip_chunk_", ".tmp"],
          @temp_dir,
          binmode: true
        )
      end
    end

    # Error raised when memory limit is exceeded
    class MemoryError < Omnizip::Error
    end
  end
end
