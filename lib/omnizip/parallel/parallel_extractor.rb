# frozen_string_literal: true

require "fractor"
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
      # Fractor Work class for extraction jobs
      class ExtractionWork < Fractor::Work
        def initialize(entry:, archive_path:, dest_dir:)
          super({
            entry: entry,
            archive_path: archive_path,
            dest_dir: dest_dir,
          })
        end

        def entry
          input[:entry]
        end

        def archive_path
          input[:archive_path]
        end

        def dest_dir
          input[:dest_dir]
        end
      end

      # Fractor Worker class for extraction
      class ExtractionWorker < Fractor::Worker
        def process(work)
          entry = work.entry
          archive_path = work.archive_path
          dest_dir = work.dest_dir

          # Read and decompress entry data (each worker opens the
          # archive independently — separate file handle per thread)
          data = read_entry_data(archive_path, entry)

          # Determine destination path
          dest_path = ::File.join(dest_dir, entry.filename)

          # Return result
          Fractor::WorkResult.new(
            result: {
              entry_name: entry.filename,
              dest_path: dest_path,
              data: data,
              directory: entry.directory?,
              unix_perms: entry.unix_permissions.to_i,
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

        def read_entry_data(archive_path, entry)
          return "" if entry.directory?

          Omnizip::Formats::Zip::Reader.new(archive_path)
            .read_entry(entry.filename)
        end
      end

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
          file_size = safe_entry_size(entry)

          job_queue.push_with_size(
            file: entry.filename,
            size: file_size,
            data: { entry: entry },
          )
        end

        # Create work items from jobs
        work_items = []
        until job_queue.empty?
          job = job_queue.pop(timeout: 0.1)
          break unless job

          work_items << ExtractionWork.new(
            entry: job.data[:entry],
            archive_path: archive,
            dest_dir: dest,
          )
        end

        # Run the worker pool through the shared engine.
        engine = Engine.new(worker_class: ExtractionWorker,
                            threads: @options.threads)
        results = []
        errors = engine.run(work_items) { |r| results << r }

        # Handle errors
        unless errors.empty?
          error_msgs = errors.map do |e|
            "#{e.work&.entry&.name}: #{e.error}"
          end.join("\n")
          raise Omnizip::DecompressionError, "Extraction errors:\n#{error_msgs}"
        end

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

        results.each do |work_result|
          result = work_result.result
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
