# frozen_string_literal: true

require "fractor"
require "fileutils"

module Omnizip
  module Parallel
    # Parallel compression coordinator using Fractor
    #
    # Manages parallel compression of files in a directory.
    # Distributes compression work across multiple workers and
    # writes results to archive in a thread-safe manner.
    #
    # @example Compress directory in parallel
    #   compressor = Omnizip::Parallel::ParallelCompressor.new(threads: 4)
    #   compressor.compress('files/', 'backup.zip')
    #
    # @example With options
    #   options = Omnizip::Models::ParallelOptions.new
    #   options.threads = 8
    #   compressor = Omnizip::Parallel::ParallelCompressor.new(options)
    #   compressor.compress('files/', 'backup.zip', compression: :lzma2)
    class ParallelCompressor
      # Fractor Work class for compression jobs
      class CompressionWork < Fractor::Work
        def initialize(file_path:, archive_path:, compression: :deflate,
level: 6)
          super({
            file_path: file_path,
            archive_path: archive_path,
            compression: compression,
            level: level,
          })
        end

        def file_path
          input[:file_path]
        end

        def archive_path
          input[:archive_path]
        end

        def compression
          input[:compression]
        end

        def level
          input[:level]
        end
      end

      # Fractor Worker class for compression
      class CompressionWorker < Fractor::Worker
        def process(work)
          file_path = work.file_path
          archive_path = work.archive_path
          compression = work.compression
          level = work.level

          # Read file data
          data = ::File.binread(file_path)
          stat = ::File.stat(file_path)

          # Compress the data
          compressed_data = compress_data(data, compression, level)

          # Calculate CRC32
          crc32 = Omnizip::Checksums::Crc32.new.tap do |c|
            c.update(data)
          end.finalize

          # Return result
          Fractor::WorkResult.new(
            result: {
              archive_path: archive_path,
              file_path: file_path,
              compressed_data: compressed_data,
              uncompressed_size: data.bytesize,
              compressed_size: compressed_data.bytesize,
              crc32: crc32,
              stat: stat,
              compression: compression,
            },
            work: work,
          )
        rescue StandardError => e
          Fractor::WorkResult.new(
            error: e,
            work: work,
          )
        end

        private

        def compress_data(data, method, level)
          case method
          when :store
            data
          when :deflate
            require "zlib"
            Zlib::Deflate.new(level, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
          when :bzip2
            Omnizip::AlgorithmRegistry.get(:bzip2).compress(data, level: level)
          when :lzma
            Omnizip::AlgorithmRegistry.get(:lzma).compress(data, level: level)
          when :lzma2
            Omnizip::AlgorithmRegistry.get(:lzma2).compress(data, level: level)
          when :zstandard
            Omnizip::AlgorithmRegistry.get(:zstandard).compress(data,
                                                                level: level)
          else
            raise Omnizip::UnsupportedFormatError,
                  "Unsupported compression: #{method}"
          end
        end
      end

      # @return [Omnizip::Models::ParallelOptions] parallel options
      attr_reader :options

      # @return [Hash] compression statistics
      attr_reader :stats

      # Initialize parallel compressor
      #
      # @param options [Omnizip::Models::ParallelOptions, Hash] parallel options
      # @param threads [Integer] number of threads (overrides options)
      def initialize(options = nil, threads: nil)
        @options = case options
                   when Omnizip::Models::ParallelOptions
                     options.dup
                   when Hash
                     Omnizip::Models::ParallelOptions.new.tap do |opts|
                       options.each do |k, v|
                         opts.send(:"#{k}=", v) if opts.respond_to?(:"#{k}=")
                       end
                     end
                   else
                     Omnizip::Models::ParallelOptions.new
                   end

        @options.threads = threads if threads
        @options.validate!

        @stats = {
          files_processed: 0,
          bytes_processed: 0,
          bytes_compressed: 0,
          start_time: nil,
          end_time: nil,
        }
      end

      # Compress directory to archive in parallel
      #
      # @param dir [String] directory path
      # @param output [String] output archive path
      # @param options [Hash] compression options
      # @option options [Symbol] :compression compression method
      # @option options [Integer] :level compression level
      # @option options [Boolean] :recursive include subdirectories
      # @option options [Proc] :progress progress callback
      # @return [String] path to created archive
      def compress(dir, output, **options)
        unless ::File.exist?(dir)
          raise Errno::ENOENT,
                "Directory not found: #{dir}"
        end
        unless ::File.directory?(dir)
          raise ArgumentError,
                "Not a directory: #{dir}"
        end

        compression = options[:compression] || :deflate
        level = options[:level] || 6
        recursive = options.fetch(:recursive, true)
        options[:progress]

        @stats[:start_time] = Time.now

        # Scan directory for files
        files = scan_directory(dir, recursive: recursive)

        # Create job queue
        job_queue = JobQueue.new(max_size: @options.queue_size)

        # Schedule jobs
        JobScheduler.new(strategy: @options.strategy)
        files.each do |file_path|
          archive_path = file_path.sub("#{dir}/", "")
          file_size = ::File.size(file_path)

          job_queue.push_with_size(
            file: file_path,
            size: file_size,
            data: {
              archive_path: archive_path,
              compression: compression,
              level: level,
            },
          )
        end

        # Create work items from jobs
        work_items = []
        until job_queue.empty?
          job = job_queue.pop(timeout: 0.1)
          break unless job

          work_items << CompressionWork.new(
            file_path: job.file,
            archive_path: job.data[:archive_path],
            compression: job.data[:compression],
            level: job.data[:level],
          )
        end

        # Create worker pool
        pool = WorkerPool.new(
          worker_class: CompressionWorker,
          num_workers: @options.threads,
          continuous: false,
        )

        pool.start
        pool.submit_batch(work_items)
        pool.run

        # Collect results
        results = pool.successful_results
        errors = pool.failed_results

        # Handle errors
        unless errors.empty?
          error_msgs = errors.map do |e|
            "#{e.work&.file_path}: #{e.error}"
          end.join("\n")
          raise Omnizip::CompressionError, "Compression errors:\n#{error_msgs}"
        end

        # Write archive sequentially (thread-safe)
        write_archive(output, results, compression: compression)

        pool.shutdown

        @stats[:end_time] = Time.now
        @stats[:files_processed] = results.size

        output
      end

      # Get compression statistics
      #
      # @return [Hash] statistics
      def statistics
        duration = if @stats[:start_time] && @stats[:end_time]
                     @stats[:end_time] - @stats[:start_time]
                   else
                     0
                   end

        @stats.merge(
          duration: duration,
          compression_ratio: calculate_compression_ratio,
          throughput_mbps: calculate_throughput(duration),
        )
      end

      private

      # Scan directory for files
      #
      # @param dir [String] directory path
      # @param recursive [Boolean] scan recursively
      # @return [Array<String>] file paths
      def scan_directory(dir, recursive: true)
        files = []

        if recursive
          Dir.glob(::File.join(dir, "**", "*")).each do |path|
            files << path if ::File.file?(path)
          end
        else
          Dir.glob(::File.join(dir, "*")).each do |path|
            files << path if ::File.file?(path)
          end
        end

        files.sort
      end

      # Write archive from compressed results
      #
      # @param output [String] output path
      # @param results [Array] compression results
      # @param compression [Symbol] compression method
      def write_archive(output, results, compression:)
        writer = Omnizip::Formats::Zip::Writer.new(output)

        results.each do |work_result|
          result = work_result.result
          next unless result

          # Add compressed entry to writer
          entry = writer.send(:create_entry,
                              filename: result[:archive_path],
                              uncompressed_data: "",
                              stat: result[:stat])

          # Override with pre-compressed data
          entry[:compressed_size] = result[:compressed_size]
          entry[:uncompressed_size] = result[:uncompressed_size]
          entry[:crc32] = result[:crc32]
          entry[:compressed_data] = result[:compressed_data]

          writer.instance_variable_get(:@entries) << entry

          @stats[:bytes_processed] += result[:uncompressed_size]
          @stats[:bytes_compressed] += result[:compressed_size]
        end

        # Write with pre-compressed data
        writer.send(:write_with_precompressed_data, compression)
      end

      # Calculate compression ratio
      #
      # @return [Float] compression ratio percentage
      def calculate_compression_ratio
        return 0.0 if @stats[:bytes_processed].zero?

        (1.0 - (@stats[:bytes_compressed].to_f / @stats[:bytes_processed])) * 100.0
      end

      # Calculate throughput in MB/s
      #
      # @param duration [Float] duration in seconds
      # @return [Float] throughput in MB/s
      def calculate_throughput(duration)
        return 0.0 if duration.zero?

        (@stats[:bytes_processed].to_f / (1024 * 1024)) / duration
      end
    end
  end
end
