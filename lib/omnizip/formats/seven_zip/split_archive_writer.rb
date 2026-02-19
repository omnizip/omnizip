# frozen_string_literal: true

require_relative "constants"
require_relative "file_collector"
require_relative "stream_compressor"
require_relative "header_writer"
require_relative "models/file_entry"
require_relative "../../models/split_options"

module Omnizip
  module Formats
    module SevenZip
      # Split archive writer for .7z format
      # Creates multi-volume archives with size limits
      class SplitArchiveWriter
        include Constants

        attr_reader :base_path, :options, :split_options, :entries, :volumes

        # Volume information
        class VolumeInfo
          attr_accessor :path, :size, :start_offset, :end_offset

          def initialize(path, start_offset = 0)
            @path = path
            @size = 0
            @start_offset = start_offset
            @end_offset = start_offset
          end
        end

        # Initialize writer
        #
        # @param base_path [String] Base path (e.g., "backup.7z.001")
        # @param options [Hash] Compression options
        # @param split_options [Models::SplitOptions] Split configuration
        def initialize(base_path, options = {}, split_options = nil)
          @base_path = base_path
          @options = {
            algorithm: :lzma2,
            level: 5,
            solid: true,
            filters: [],
          }.merge(options)
          @split_options = split_options || Models::SplitOptions.new
          @split_options.validate!
          @collector = FileCollector.new
          @entries = []
          @volumes = []
          @current_volume = nil
          @current_volume_number = 1
          @global_offset = 0
        end

        # Add file to archive
        #
        # @param file_path [String] Path to file
        # @param archive_path [String, nil] Path in archive
        def add_file(file_path, archive_path = nil)
          @collector.add_path(file_path, archive_path: archive_path,
                                         recursive: false)
        end

        # Add directory to archive
        #
        # @param dir_path [String] Path to directory
        # @param recursive [Boolean] Add contents recursively
        def add_directory(dir_path, recursive: true)
          @collector.add_path(dir_path, recursive: recursive)
        end

        # Add files matching glob pattern
        #
        # @param pattern [String] Glob pattern
        def add_files(pattern)
          @collector.add_glob(pattern)
        end

        # Write split archive
        #
        # @raise [RuntimeError] on write error
        def write
          # Collect files
          @entries = @collector.collect_files

          # Determine spanning strategy
          if @split_options.span_strategy == Omnizip::Models::SplitOptions::STRATEGY_BALANCED
            write_balanced
          else
            write_first_fit
          end
        end

        private

        # Write using first-fit strategy (default)
        def write_first_fit
          # Compress all files first
          compressed_result = compress_files

          # Calculate total size needed
          compressed_result[:data].bytesize
          header_data = build_next_header(compressed_result)
          header_data.bytesize

          # Create volumes and write data
          start_first_volume
          write_packed_data(compressed_result[:data])

          # Write header at the end of last volume
          header_offset = @global_offset - START_HEADER_SIZE
          write_data(header_data)

          # Write start header to first volume (this closes volumes)
          write_start_header_to_first_volume(header_data, header_offset)
        end

        # Write using balanced strategy
        # Pre-calculates optimal file distribution
        def write_balanced
          # For now, use first-fit strategy
          # Full balanced implementation would require:
          # 1. Calculate individual file sizes
          # 2. Use bin-packing algorithm
          # 3. Distribute files optimally
          write_first_fit
        end

        # Compress all files
        #
        # @return [Hash] Compression results
        def compress_files
          compressor = StreamCompressor.new(
            algorithm: @options[:algorithm],
            level: @options[:level],
            filters: @options[:filters],
          )

          files_with_data = @entries.select(&:has_stream?)

          if @options[:solid]
            # Solid: compress all files into one stream
            result = compressor.compress_files(files_with_data)
            files_with_data.each_with_index do |entry, i|
              entry.crc = result[:crcs][i]
              entry.size = result[:unpack_sizes][i]
            end

            {
              data: result[:packed_data],
              folders: [{
                method_id: compressor.method_id,
                properties: compressor.properties,
                unpack_size: result[:unpack_size],
              }],
              pack_sizes: [result[:packed_size]],
              unpack_sizes: result[:unpack_sizes],
              digests: result[:crcs],
            }
          else
            # Non-solid: compress each file separately
            packed_data = String.new(encoding: "BINARY")
            folders = []
            pack_sizes = []
            unpack_sizes = []
            digests = []

            files_with_data.each do |entry|
              data = File.binread(entry.source_path)
              compressed = compressor.compress(data)

              packed_data << compressed
              pack_sizes << compressed.bytesize
              unpack_sizes << data.bytesize

              # Calculate CRC
              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              entry.crc = crc.value
              digests << crc.value

              folders << {
                method_id: compressor.method_id,
                properties: compressor.properties,
                unpack_size: data.bytesize,
              }
            end

            {
              data: packed_data,
              folders: folders,
              pack_sizes: pack_sizes,
              unpack_sizes: unpack_sizes,
              digests: digests,
            }
          end
        end

        # Build next header metadata
        #
        # @param compressed_result [Hash] Compression results
        # @return [String] Encoded next header
        def build_next_header(compressed_result)
          header_writer = HeaderWriter.new

          header_options = {
            streams: {
              pack_pos: 0,
              pack_sizes: compressed_result[:pack_sizes],
              pack_crcs: [],
              folders: compressed_result[:folders],
              unpack_sizes: compressed_result[:unpack_sizes],
              digests: compressed_result[:digests],
            },
            entries: @entries,
          }

          header_writer.write_next_header(header_options)
        end

        # Start first volume
        def start_first_volume
          volume_path = @split_options.volume_filename(@base_path, 1)
          @current_volume = File.open(volume_path, "wb")
          @volumes << VolumeInfo.new(volume_path, 0)

          # Reserve space for start header (will be written at end)
          @current_volume.write("\0" * START_HEADER_SIZE)
          @global_offset = START_HEADER_SIZE
          @volumes.last.size = START_HEADER_SIZE
          @volumes.last.end_offset = START_HEADER_SIZE
        end

        # Write packed data across volumes
        #
        # @param data [String] Data to write
        def write_packed_data(data)
          offset = 0
          remaining = data.bytesize

          while remaining.positive?
            available = @split_options.volume_size - @volumes.last.size

            # If current volume is full, start a new one
            if available <= 0
              close_current_volume
              start_continuation_volume
              available = @split_options.volume_size
            end

            chunk_size = [available, remaining].min

            if chunk_size.positive?
              chunk = data[offset, chunk_size]
              @current_volume.write(chunk)
              @volumes.last.size += chunk_size
              @volumes.last.end_offset += chunk_size
              @global_offset += chunk_size
              offset += chunk_size
              remaining -= chunk_size
            end
          end
        end

        # Write data (may span volumes)
        #
        # @param data [String] Data to write
        def write_data(data)
          write_packed_data(data)
        end

        # Start continuation volume
        def start_continuation_volume
          @current_volume_number += 1
          volume_path = @split_options.volume_filename(@base_path,
                                                       @current_volume_number)
          @current_volume = File.open(volume_path, "wb")
          @volumes << VolumeInfo.new(volume_path, @global_offset)
        end

        # Write start header to first volume
        #
        # @param header_data [String] Header data
        # @param header_offset [Integer] Offset to header
        def write_start_header_to_first_volume(header_data, header_offset)
          # Close current volume first to ensure all data is flushed
          close_current_volume

          header_writer = HeaderWriter.new
          start_header = header_writer.write_start_header(
            header_data,
            header_offset,
          )

          # Open first volume and write start header
          first_volume_path = @volumes.first.path
          File.open(first_volume_path, "r+b") do |io|
            io.seek(0)
            io.write(start_header)
            io.flush
          end
        end

        # Close current volume
        def close_current_volume
          return unless @current_volume

          @current_volume.flush
          @current_volume.close
          @current_volume = nil
        end
      end
    end
  end
end
