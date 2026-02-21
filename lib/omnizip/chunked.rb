# frozen_string_literal: true

module Omnizip
  # Chunked processing for memory-efficient large file handling
  module Chunked
    autoload :Reader, "omnizip/chunked/reader"
    autoload :Writer, "omnizip/chunked/writer"
    autoload :MemoryManager, "omnizip/chunked/memory_manager"

    # Configuration for chunked operations
    class Configuration
      attr_accessor :chunk_size, :max_memory, :temp_directory, :spill_strategy

      def initialize
        @chunk_size = 64 * 1024 * 1024 # 64MB
        @max_memory = 256 * 1024 * 1024 # 256MB
        @temp_directory = nil # Use system default
        @spill_strategy = :disk # or :error
      end
    end

    class << self
      # Global configuration
      def configuration
        @configuration ||= Configuration.new
      end

      # Configure chunked operations
      # @yield [config] Configuration block
      def configure
        yield configuration
      end

      # Compress file with chunked processing
      # @param input [String] Input file path
      # @param output [String] Output file path
      # @param options [Hash] Compression options
      # @option options [Integer] :chunk_size Chunk size in bytes
      # @option options [Integer] :max_memory Maximum memory usage in bytes
      # @option options [Symbol] :compression Compression method
      # @option options [Proc] :progress Progress callback
      # @return [String] Output file path
      def compress_file(input, output, **options)
        chunk_size = options[:chunk_size] || configuration.chunk_size
        options[:max_memory] || configuration.max_memory
        progress = options[:progress]

        unless File.exist?(input)
          raise Errno::ENOENT,
                "Input file not found: #{input}"
        end

        reader = Reader.new(input, chunk_size: chunk_size)
        total_size = reader.total_size
        processed = 0

        Omnizip::Zip::File.create(output) do |zip|
          basename = File.basename(input)

          # Use add with a block instead of private add_data
          zip.add(basename) do
            data = String.new(encoding: Encoding::BINARY)

            reader.each_chunk do |chunk|
              data << chunk
              processed += chunk.bytesize

              if progress
                percentage = (processed.to_f / total_size * 100).round(2)
                progress.call(processed, total_size, percentage)
              end
            end

            data
          end
        end

        output
      end

      # Decompress file with chunked processing
      # @param input [String] Input archive path
      # @param output [String] Output file path
      # @param options [Hash] Decompression options
      # @option options [Integer] :chunk_size Chunk size in bytes
      # @option options [Proc] :progress Progress callback
      # @return [String] Output file path
      def decompress_file(input, output, **options)
        chunk_size = options[:chunk_size] || configuration.chunk_size
        progress = options[:progress]

        unless File.exist?(input)
          raise Errno::ENOENT,
                "Input archive not found: #{input}"
        end

        writer = Writer.new(output, chunk_size: chunk_size)
        processed = 0

        Omnizip::Zip::File.open(input) do |zip|
          entry = zip.entries.first
          total_size = entry.size

          # Read the full entry content
          content = zip.get_input_stream(entry)

          # Write in chunks
          offset = 0
          while offset < content.bytesize
            chunk = content.byteslice(offset, chunk_size) || ""
            break if chunk.empty?

            writer.write_chunk(chunk)
            processed += chunk.bytesize
            offset += chunk.bytesize

            if progress
              percentage = (processed.to_f / total_size * 100).round(2)
              progress.call(processed, total_size, percentage)
            end
          end
        end

        writer.close
        output
      end
    end
  end
end
