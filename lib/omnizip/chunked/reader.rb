# frozen_string_literal: true

module Omnizip
  module Chunked
    # Read large files in chunks for memory-efficient processing
    class Reader
      DEFAULT_CHUNK_SIZE = 64 * 1024 * 1024 # 64MB

      attr_reader :file_path, :chunk_size, :total_size

      # Initialize a chunked reader
      # @param file_path [String] Path to file to read
      # @param options [Hash] Reader options
      # @option options [Integer] :chunk_size Chunk size in bytes
      def initialize(file_path, chunk_size: DEFAULT_CHUNK_SIZE)
        @file_path = file_path
        @chunk_size = chunk_size
        @total_size = File.size(file_path)
        @position = 0
      end

      # Read next chunk from file
      # @return [String, nil] Chunk data or nil if EOF
      def read_chunk
        return nil if @position >= @total_size

        File.open(@file_path, "rb") do |f|
          f.seek(@position)
          chunk = f.read(@chunk_size)
          @position += chunk.bytesize if chunk
          chunk
        end
      end

      # Iterate through all chunks
      # @yield [chunk, position, total] Block called for each chunk
      def each_chunk
        reset
        while (chunk = read_chunk)
          yield chunk, @position - chunk.bytesize, @total_size
        end
      end

      # Get current progress as percentage
      # @return [Float] Progress from 0.0 to 1.0
      def progress
        return 1.0 if @total_size.zero?

        @position.to_f / @total_size
      end

      # Reset reader to beginning of file
      # @return [self]
      def reset
        @position = 0
        self
      end

      # Check if at end of file
      # @return [Boolean] True if at EOF
      def eof?
        @position >= @total_size
      end

      # Get number of chunks needed for file
      # @return [Integer] Number of chunks
      def chunk_count
        (@total_size.to_f / @chunk_size).ceil
      end

      # Get remaining bytes to read
      # @return [Integer] Remaining bytes
      def remaining
        @total_size - @position
      end
    end
  end
end
