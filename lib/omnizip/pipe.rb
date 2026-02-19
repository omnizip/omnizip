# frozen_string_literal: true

require_relative "pipe/stream_compressor"
require_relative "pipe/stream_decompressor"

module Omnizip
  # Unix pipe operations for stdin/stdout integration
  #
  # Enables compression and decompression through Unix pipes without
  # temporary files, supporting container workflows, CI/CD pipelines,
  # and stream processing scenarios.
  #
  # @example Compress stdin to stdout
  #   Omnizip::Pipe.compress($stdin, $stdout, format: :zip)
  #
  # @example Decompress stdin to directory
  #   Omnizip::Pipe.decompress($stdin, output_dir: 'extracted/')
  #
  # @example File-to-file via pipe
  #   File.open('input.txt', 'rb') do |input|
  #     File.open('output.zip', 'wb') do |output|
  #       Omnizip::Pipe.compress(input, output, format: :zip)
  #     end
  #   end
  module Pipe
    class << self
      # Compress from input stream to output stream
      #
      # @param input [IO] Input stream (stdin, File, Socket, etc.)
      # @param output [IO] Output stream (stdout, File, network, etc.)
      # @param format [Symbol] Archive format (:zip, :seven_zip)
      # @param compression [Symbol] Compression algorithm
      # @param options [Hash] Additional compression options
      # @option options [String] :entry_name Name for entry in archive
      # @option options [Integer] :chunk_size Read buffer size (default 64KB)
      # @option options [Integer] :level Compression level (1-9)
      # @return [Integer] Number of bytes written
      #
      # @example Compress stdin to stdout
      #   Omnizip::Pipe.compress($stdin, $stdout, format: :zip)
      #
      # @example Compress file with custom options
      #   File.open('data.txt', 'rb') do |input|
      #     File.open('data.zip', 'wb') do |output|
      #       Omnizip::Pipe.compress(
      #         input, output,
      #         format: :zip,
      #         compression: :deflate,
      #         level: 9,
      #         entry_name: 'data.txt'
      #       )
      #     end
      #   end
      def compress(input, output, format: :zip, compression: nil, **options)
        compressor = Pipe::StreamCompressor.new(
          input,
          output,
          format,
          compression: compression,
          **options,
        )
        compressor.compress
      end

      # Decompress from input stream
      #
      # @param input [IO] Input stream containing archive
      # @param output_dir [String, nil] Directory to extract to (nil = stdout)
      # @param options [Hash] Extraction options
      # @return [Integer, Hash] Bytes written or extracted files hash
      #
      # @example Extract to directory
      #   Omnizip::Pipe.decompress($stdin, output_dir: 'extracted/')
      #
      # @example Extract to stdout (single file)
      #   Omnizip::Pipe.decompress($stdin, output: $stdout)
      def decompress(input, output_dir: nil, output: nil, **options)
        decompressor = Pipe::StreamDecompressor.new(
          input,
          output_dir: output_dir,
          output: output,
          **options,
        )
        decompressor.decompress
      end

      # Check if running in pipe mode
      #
      # Detects if stdin/stdout are pipes (not TTY), indicating
      # the program is being used in a Unix pipeline.
      #
      # @return [Boolean] True if stdin and stdout are pipes
      #
      # @example
      #   if Omnizip::Pipe.pipe_mode?
      #     # Process stdin to stdout
      #   else
      #     # Show interactive help
      #   end
      def pipe_mode?
        !$stdin.tty? && !$stdout.tty?
      end

      # Detect if input is stdin
      #
      # @param input [String, IO] Input path or IO object
      # @return [Boolean] True if input is stdin
      def stdin?(input)
        ["-", $stdin].include?(input)
      end

      # Detect if output is stdout
      #
      # @param output [String, IO] Output path or IO object
      # @return [Boolean] True if output is stdout
      def stdout?(output)
        ["-", $stdout].include?(output)
      end
    end
  end
end
