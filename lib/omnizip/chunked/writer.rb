# frozen_string_literal: true

module Omnizip
  module Chunked
    # Write large files incrementally in chunks
    class Writer
      DEFAULT_CHUNK_SIZE = 64 * 1024 * 1024 # 64MB
      FLUSH_THRESHOLD = 10 # Flush every N chunks

      attr_reader :output_path, :chunk_size, :written

      # Initialize a chunked writer
      # @param output_path [String] Path to output file
      # @param options [Hash] Writer options
      # @option options [Integer] :chunk_size Chunk size in bytes
      def initialize(output_path, chunk_size: DEFAULT_CHUNK_SIZE)
        @output_path = output_path
        @chunk_size = chunk_size
        @written = 0
        @chunks_written = 0
        @file_handle = nil
      end

      # Write a chunk to file
      # @param chunk [String] Data to write
      # @return [Integer] Bytes written
      def write_chunk(chunk)
        ensure_file_open

        bytes = @file_handle.write(chunk)
        @written += bytes
        @chunks_written += 1

        # Flush periodically to disk
        flush if (@chunks_written % FLUSH_THRESHOLD).zero?

        bytes
      end

      # Write data from a source in chunks
      # @param source [String, IO] Source to read from
      # @return [Integer] Total bytes written
      def write_from(source)
        case source
        when String
          # File path
          if File.exist?(source)
            Reader.new(source, chunk_size: @chunk_size).each_chunk do |chunk|
              write_chunk(chunk)
            end
          else
            # Treat as data
            write_chunk(source)
          end
        when IO, StringIO
          # IO object
          while (chunk = source.read(@chunk_size))
            break if chunk.empty?

            write_chunk(chunk)
          end
        else
          raise ArgumentError, "Unsupported source type: #{source.class}"
        end

        @written
      end

      # Flush buffered data to disk
      # @return [self]
      def flush
        @file_handle&.flush
        self
      end

      # Close the file handle
      # @return [self]
      def close
        if @file_handle
          flush
          @file_handle.close
          @file_handle = nil
        end
        self
      end

      # Finalize the file (alias for close)
      # @return [self]
      def finish
        close
      end

      # Execute block with writer, auto-close
      # @yield [writer] Block to write data
      # @return [Integer] Total bytes written
      def self.with_writer(output_path, **options)
        writer = new(output_path, **options)
        begin
          yield writer
          writer.written
        ensure
          writer.close
        end
      end

      private

      # Ensure file handle is open
      def ensure_file_open
        return if @file_handle

        # Create parent directory if needed
        dir = File.dirname(@output_path)
        FileUtils.mkdir_p(dir)

        @file_handle = File.open(@output_path, "wb")
      end
    end
  end
end
