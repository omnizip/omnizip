# frozen_string_literal: true

module Omnizip
  module Pipe
    # Stream-based compression for pipe operations
    #
    # Accepts any IO-like input source and writes compressed output
    # to any IO-like sink, using chunk-based processing to avoid
    # loading entire streams into memory.
    #
    # @example Compress stdin to stdout
    #   compressor = StreamCompressor.new($stdin, $stdout, :zip)
    #   compressor.compress
    #
    # @example Compress with custom chunk size
    #   compressor = StreamCompressor.new(
    #     input_file,
    #     output_file,
    #     :zip,
    #     chunk_size: 1024 * 1024  # 1MB chunks
    #   )
    #   compressor.compress
    class StreamCompressor
      # Default chunk size for reading input (64KB)
      DEFAULT_CHUNK_SIZE = 64 * 1024

      attr_reader :input, :output, :format, :options, :bytes_written

      # Initialize stream compressor
      #
      # @param input [IO] Input stream to compress
      # @param output [IO] Output stream for compressed data
      # @param format [Symbol] Archive format (:zip, :seven_zip)
      # @param compression [Symbol, nil] Compression algorithm
      # @param options [Hash] Compression options
      # @option options [String] :entry_name Name for entry (default: 'stream.dat')
      # @option options [Integer] :chunk_size Read buffer size
      # @option options [Integer] :level Compression level (1-9)
      # @option options [Proc] :progress Progress callback
      def initialize(input, output, format, compression: nil, **options)
        @input = input
        @output = output
        @format = format
        @compression = compression
        @options = options
        @chunk_size = options[:chunk_size] || DEFAULT_CHUNK_SIZE
        @bytes_read = 0
        @bytes_written = 0
        @progress_callback = options[:progress]
      end

      # Compress input stream to output stream
      #
      # Reads input in chunks and writes compressed output,
      # maintaining constant memory usage regardless of input size.
      #
      # @return [Integer] Total bytes written to output
      # @raise [ArgumentError] If format is unsupported
      def compress
        case @format
        when :zip
          compress_zip
        when :seven_zip, :"7z"
          compress_7z
        else
          raise ArgumentError, "Unsupported format: #{@format}"
        end

        @bytes_written
      end

      private

      # Compress to ZIP format
      #
      # Creates a single-entry ZIP archive from the input stream.
      # Uses chunked reading to handle arbitrarily large inputs.
      def compress_zip
        entry_name = @options[:entry_name] || "stream.dat"
        level = @options[:level]

        Omnizip::Zip::OutputStream.open(@output) do |zos|
          # Create entry with optional compression level
          entry_options = {}
          entry_options[:level] = level if level

          zos.put_next_entry(entry_name, **entry_options)

          # Stream chunks from input to output
          stream_chunks(zos)
        end
      end

      # Compress to 7z format
      #
      # Note: 7z streaming support is limited due to format requirements.
      # For full 7z support, use file-based operations.
      def compress_7z
        raise NotImplementedError,
              "7z pipe compression not yet implemented. " \
              "Use file-based operations for 7z format."
      end

      # Stream data in chunks from input to output
      #
      # @param output_stream [IO] Stream to write chunks to
      def stream_chunks(output_stream)
        loop do
          chunk = @input.read(@chunk_size)
          break unless chunk

          output_stream.write(chunk)
          @bytes_read += chunk.bytesize
          @bytes_written += chunk.bytesize

          # Call progress callback if provided
          if @progress_callback
            @progress_callback.call(@bytes_read, @bytes_written)
          end
        end
      rescue IOError, SystemCallError => e
        raise Omnizip::Error, "Stream compression failed: #{e.message}"
      end
    end
  end
end