# frozen_string_literal: true

require "fileutils"

module Omnizip
  module Pipe
    # Stream-based decompression for pipe operations
    #
    # Accepts compressed archive from any IO-like source and extracts
    # to directory or streams to output. Handles multi-file archives
    # and provides error recovery for corrupted streams.
    #
    # @example Decompress to directory
    #   decompressor = StreamDecompressor.new($stdin, output_dir: 'extracted/')
    #   decompressor.decompress
    #
    # @example Decompress to stdout
    #   decompressor = StreamDecompressor.new($stdin, output: $stdout)
    #   decompressor.decompress
    class StreamDecompressor
      # Default chunk size for streaming extraction (64KB)
      DEFAULT_CHUNK_SIZE = 64 * 1024

      attr_reader :input, :output_dir, :output, :options, :bytes_written

      # Initialize stream decompressor
      #
      # @param input [IO] Input stream containing archive
      # @param output_dir [String, nil] Directory to extract to
      # @param output [IO, nil] Output stream (for single-file extraction)
      # @param options [Hash] Decompression options
      # @option options [Symbol] :format Archive format (auto-detected if nil)
      # @option options [Integer] :chunk_size Write buffer size
      # @option options [Proc] :progress Progress callback
      # @option options [Boolean] :preserve_paths Preserve directory structure
      def initialize(input, output_dir: nil, output: nil, **options)
        @input = input
        @output_dir = output_dir
        @output = output
        @options = options
        @chunk_size = options[:chunk_size] || DEFAULT_CHUNK_SIZE
        @bytes_written = 0
        @progress_callback = options[:progress]
        @format = options[:format]
        @preserve_paths = options.fetch(:preserve_paths, true)
      end

      # Decompress input stream
      #
      # Extracts archive to output directory or streams to output.
      # Returns hash of extracted files or bytes written.
      #
      # @return [Hash<String, Integer>, Integer] Files => bytes or total bytes
      # @raise [Omnizip::FormatError] If archive format is invalid
      def decompress
        if @output
          decompress_to_stream
        elsif @output_dir
          decompress_to_directory
        else
          raise ArgumentError,
                "Either output_dir or output must be specified"
        end
      end

      private

      # Decompress to output stream
      #
      # Extracts first non-directory entry to output stream.
      # Useful for single-file archives or piping to stdout.
      #
      # @return [Integer] Bytes written to output
      def decompress_to_stream
        # Read archive into memory (necessary for format detection)
        archive_data = @input.read

        Omnizip::Buffer.open(archive_data, format: @format) do |archive|
          archive.each_entry do |entry|
            next if entry.directory?

            # Stream first file to output
            while chunk = entry.read(@chunk_size)
              @output.write(chunk)
              @bytes_written += chunk.bytesize

              if @progress_callback
                @progress_callback.call(entry.name, @bytes_written)
              end
            end

            break # Only extract first file for streaming
          end
        end

        @bytes_written
      rescue StandardError => e
        raise Omnizip::Error,
              "Stream decompression failed: #{e.message}"
      end

      # Decompress to directory
      #
      # Extracts all entries to specified directory with
      # directory structure preservation.
      #
      # @return [Hash<String, Integer>] Filename => bytes mapping
      def decompress_to_directory
        FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)

        # Read archive into memory
        archive_data = @input.read
        extracted_files = {}

        Omnizip::Buffer.open(archive_data, format: @format) do |archive|
          archive.each_entry do |entry|
            if entry.directory?
              create_directory(entry)
            else
              bytes = extract_file(entry)
              extracted_files[entry.name] = bytes
            end
          end
        end

        extracted_files
      rescue StandardError => e
        raise Omnizip::Error,
              "Directory extraction failed: #{e.message}"
      end

      # Create directory from entry
      #
      # @param entry [Object] Directory entry
      def create_directory(entry)
        return unless @preserve_paths

        dir_path = File.join(@output_dir, entry.name)
        FileUtils.mkdir_p(dir_path)
      end

      # Extract file from entry
      #
      # @param entry [Object] File entry
      # @return [Integer] Bytes written
      def extract_file(entry)
        dest_path = @preserve_paths ?
                    File.join(@output_dir, entry.name) :
                    File.join(@output_dir, File.basename(entry.name))

        # Create parent directory if needed
        FileUtils.mkdir_p(File.dirname(dest_path))

        bytes = 0
        File.open(dest_path, "wb") do |file|
          while chunk = entry.read(@chunk_size)
            file.write(chunk)
            bytes += chunk.bytesize
            @bytes_written += chunk.bytesize

            if @progress_callback
              @progress_callback.call(entry.name, @bytes_written)
            end
          end
        end

        # Preserve timestamp if available
        if entry.respond_to?(:mtime) && entry.mtime
          File.utime(entry.mtime, entry.mtime, dest_path)
        end

        bytes
      end
    end
  end
end