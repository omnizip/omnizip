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

          # Read and decompress entry data
          data = read_entry_data(archive_path, entry)

          # Determine destination path
          dest_path = ::File.join(dest_dir, entry.name)

          # Return result
          Fractor::WorkResult.new(
            result: {
              entry_name: entry.name,
              dest_path: dest_path,
              data: data,
              directory: entry.directory?,
              unix_perms: entry.respond_to?(:unix_perms) ? entry.unix_perms : 0,
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

          # Open archive and extract entry
          reader = Omnizip::Formats::Zip::Reader.new(archive_path)
          reader.read

          ::File.open(archive_path, "rb") do |io|
            # Find the entry in reader
            reader_entry = reader.entries.find { |e| e.filename == entry.name }
            raise "Entry not found in archive: #{entry.name}" unless reader_entry

            # Seek to entry data
            io.seek(reader_entry.local_header_offset, ::IO::SEEK_SET)

            # Read and parse local file header
            fixed_header = io.read(30)
            return "" unless fixed_header && fixed_header.size == 30

            _signature, _version, _flags, _method, _time, _date, _crc32,
            _comp_size, _uncomp_size, filename_length, extra_length = fixed_header.unpack("VvvvvvVVVvv")

            # Skip filename and extra field
            io.read(filename_length + extra_length)

            # Read compressed data
            compressed_data = io.read(reader_entry.compressed_size)
            return "" unless compressed_data

            # Decompress
            reader.send(:decompress_data,
                        compressed_data,
                        reader_entry.compression_method,
                        reader_entry.uncompressed_size)
          end
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
          file_size = entry.respond_to?(:size) ? entry.size : 0

          job_queue.push_with_size(
            file: entry.name,
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

        # Create worker pool
        pool = WorkerPool.new(
          worker_class: ExtractionWorker,
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
            "#{e.work&.entry&.name}: #{e.error}"
          end.join("\n")
          raise Omnizip::ExtractionError, "Extraction errors:\n#{error_msgs}"
        end

        # Write files to disk (thread-safe)
        extracted_paths = write_extracted_files(results, overwrite: overwrite)

        pool.shutdown

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

      # Read archive entries
      #
      # @param archive_path [String] archive path
      # @return [Array<Entry>] array of entries
      def read_archive_entries(archive_path)
        entries = []

        Omnizip::Zip::File.open(archive_path) do |zip|
          zip.each do |entry|
            entries << entry
          end
        end

        entries
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
            # Check if file exists
            if ::File.exist?(dest_path) && !overwrite
              raise "File exists: #{dest_path}"
            end

            # Write file or create directory
            if result[:directory]
              FileUtils.mkdir_p(dest_path)
            else
              FileUtils.mkdir_p(::File.dirname(dest_path))
              ::File.binwrite(dest_path, result[:data])

              # Set permissions if Unix
              if result[:unix_perms].positive?
                ::File.chmod(result[:unix_perms] & 0o777, dest_path)
              end

              @stats[:bytes_extracted] += result[:data].bytesize
            end

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
