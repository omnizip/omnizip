# frozen_string_literal: true

require "fileutils"

module Omnizip
  module Parallel
    # Parallel extraction coordinator using Fractor
    #
    # Manages parallel extraction of files from an archive.
    # Distributes extraction work across multiple workers and
    # writes files to disk in a thread-safe manner.
    #
    # @example Extract archive in parallel
    #   extractor = Omnizip::Parallel::ParallelExtractor.new(threads: 4)
    #   extractor.extract('backup.zip', 'output/')
    #
    # @example With options
    #   options = Omnizip::Models::ParallelOptions.new
    #   options.threads = 8
    #   extractor = Omnizip::Parallel::ParallelExtractor.new(options)
    #   extractor.extract('backup.zip', 'output/')
    class ParallelExtractor
      # @return [Omnizip::Models::ParallelOptions] parallel options
      attr_reader :options

      # @return [Hash] extraction statistics
      attr_reader :stats

      # Initialize parallel extractor
      #
      # @param options [Omnizip::Models::ParallelOptions, Hash] parallel options
      # @param threads [Integer] number of threads (overrides options)
      def initialize(options = nil, threads: nil)
        @options = case options
                   when Omnizip::Models::ParallelOptions
                     options.dup
                   when Hash
                     Omnizip::Models::ParallelOptions.new.apply(options)
                   else
                     Omnizip::Models::ParallelOptions.new
                   end

        @options.threads = threads if threads
        @options.validate_options!

        @stats = {
          files_extracted: 0,
          bytes_extracted: 0,
          start_time: nil,
          end_time: nil,
        }

        @write_mutex = Mutex.new
      end

      # Extract archive to directory in parallel
      #
      # @param archive [String] archive path
      # @param dest [String] destination directory
      # @param options [Hash] extraction options
      # @option options [Boolean] :overwrite overwrite existing files
      # @option options [Proc] :progress progress callback
      # @return [Array<String>] extracted file paths
      def extract(archive, dest, **options)
        unless ::File.exist?(archive)
          raise Errno::ENOENT,
                "Archive not found: #{archive}"
        end

        overwrite = options.fetch(:overwrite, false)
        options[:progress]

        @stats[:start_time] = Time.now

        # Read archive to get entries
        entries = read_archive_entries(archive)

        # Create destination directory
        FileUtils.mkdir_p(dest)

        # Create job queue
        job_queue = JobQueue.new(max_size: @options.queue_size)

        # Schedule jobs
        entries.each do |entry|
          job_queue.push_with_size(
            file: entry.filename,
            size: safe_entry_size(entry),
            data: { entry_name: entry.filename },
          )
        end

        # Create work items from jobs, largest first
        work_items = []
        until job_queue.empty?
          job = job_queue.pop(timeout: 0.1)
          break unless job

          work_items << job.data[:entry_name]
        end

        # Threads, not Ractors: Omnizip's autoloads and Proc-holding
        # codec constants cannot cross Ractor boundaries on Ruby <= 3.3
        pool = ThreadPool.new(size: @options.threads)
        raw_results, raw_errors = pool.map(work_items) do |entry_name|
          process_entry(archive, dest, entry_name)
        end

        # Handle errors (raw_errors holds nil for every item that
        # succeeded — zip+compact would keep those pairs)
        failure_pairs = raw_errors.each_with_index.filter_map do |error, index|
          [work_items[index], error] if error
        end
        unless failure_pairs.empty?
          error_msgs = failure_pairs.map { |name, e| "#{name}: #{e.message}" }
            .join("\n")
          raise Omnizip::DecompressionError, "Extraction errors:\n#{error_msgs}"
        end

        results = raw_results

        # Write files to disk (thread-safe)
        extracted_paths = write_extracted_files(results, overwrite: overwrite)

        @stats[:end_time] = Time.now
        @stats[:files_extracted] = results.size

        extracted_paths
      end

      # Get extraction statistics
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
          throughput_mbps: calculate_throughput(duration),
        )
      end

      private

      # Decompress one entry in a worker thread. Each worker opens
      # the archive independently — its own file handle per thread.
      def process_entry(archive_path, dest_dir, entry_name)
        entry = Omnizip::Formats::Zip::Reader.new(archive_path)
          .entries.find { |e| e.filename == entry_name }
        raise Errno::ENOENT, "Entry not found: #{entry_name}" unless entry

        {
          entry_name: entry_name,
          dest_path: ::File.join(dest_dir, entry_name),
          data: entry.directory? ? "" : read_entry_data(archive_path, entry_name),
          directory: entry.directory?,
          unix_perms: entry.unix_permissions.to_i,
        }
      end

      def read_entry_data(archive_path, entry_name)
        Omnizip::Formats::Zip::Reader.new(archive_path)
          .read_entry(entry_name)
      end

      def safe_entry_size(entry)
        entry.uncompressed_size.to_i
      end

      # Read archive entries through the native reader
      #
      # @param archive_path [String] archive path
      # @return [Array<CentralDirectoryHeader>] array of entries
      def read_archive_entries(archive_path)
        Omnizip::Formats::Zip::Reader.new(archive_path).entries
      end

      # Write extracted files to disk
      #
      # @param results [Array] extraction results
      # @param overwrite [Boolean] overwrite existing files
      # @return [Array<String>] extracted file paths
      def write_extracted_files(results, overwrite: false)
        extracted_paths = []

        results.each do |result|
          next unless result

          dest_path = result[:dest_path]

          # Thread-safe file writing
          @write_mutex.synchronize do
            if result[:directory]
              # mkdir_p is idempotent — a file entry may already have
              # created this directory as its parent
              FileUtils.mkdir_p(dest_path)
              extracted_paths << dest_path
              next
            end

            # Check if file exists
            if ::File.exist?(dest_path) && !overwrite
              raise Errno::EEXIST, "File exists: #{dest_path}"
            end

            FileUtils.mkdir_p(::File.dirname(dest_path))
            ::File.binwrite(dest_path, result[:data])

            # Set permissions if Unix
            if result[:unix_perms].positive?
              ::File.chmod(result[:unix_perms] & 0o777, dest_path)
            end

            @stats[:bytes_extracted] += result[:data].bytesize

            extracted_paths << dest_path
          end
        end

        extracted_paths
      end

      # Calculate throughput in MB/s
      #
      # @param duration [Float] duration in seconds
      # @return [Float] throughput in MB/s
      def calculate_throughput(duration)
        return 0.0 if duration.zero?

        (@stats[:bytes_extracted].to_f / (1024 * 1024)) / duration
      end
    end
  end
end
