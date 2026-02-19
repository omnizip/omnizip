# frozen_string_literal: true

require_relative "volume_splitter"
require_relative "volume_writer"
require_relative "../models/volume_options"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module MultiVolume
          # Volume manager for multi-volume archive creation
          #
          # This class coordinates the creation of multi-volume RAR5 archives
          # by managing volume splitting, file distribution, and volume writing.
          #
          # @example Create multi-volume archive
          #   manager = VolumeManager.new('archive.rar',
          #     max_volume_size: 10 * 1024 * 1024,  # 10 MB
          #     compression: :lzma,
          #     level: 5
          #   )
          #   manager.add_file('large_file.dat')
          #   manager.create_volumes
          class VolumeManager
            # @return [String] Base archive path
            attr_reader :base_path

            # @return [VolumeOptions] Volume options
            attr_reader :volume_options

            # @return [Hash] Compression options
            attr_reader :compression_options

            # @return [Array<Hash>] Files to archive
            attr_reader :files

            # Initialize volume manager
            #
            # @param base_path [String] Base archive path (e.g., "archive.rar")
            # @param options [Hash] Options
            # @option options [Integer] :max_volume_size Maximum volume size in bytes
            # @option options [String] :volume_naming Naming pattern ("part", "volume", "numeric")
            # @option options [Symbol] :compression Compression method (:store, :lzma)
            # @option options [Integer] :level Compression level (1-5)
            # @option options [Boolean] :include_mtime Include modification time
            # @option options [Boolean] :include_crc32 Include CRC32
            def initialize(base_path, options = {})
              @base_path = base_path
              @volume_options = Models::VolumeOptions.new(
                max_volume_size: options[:max_volume_size] || 104_857_600,
                volume_naming: options[:volume_naming] || "part",
              )
              @volume_options.validate!

              @compression_options = {
                compression: options[:compression] || :store,
                level: options[:level] || 3,
                include_mtime: options[:include_mtime] || false,
                include_crc32: options[:include_crc32] || false,
              }

              @files = []
            end

            # Add file to archive
            #
            # @param input_path [String] Path to file on disk
            # @param archive_path [String, nil] Path within archive
            # @return [void]
            def add_file(input_path, archive_path = nil)
              unless File.exist?(input_path)
                raise ArgumentError,
                      "File not found: #{input_path}"
              end

              archive_path ||= File.basename(input_path)

              @files << {
                input: input_path,
                archive: archive_path,
                mtime: File.mtime(input_path),
                stat: File.stat(input_path),
                size: File.size(input_path),
              }
            end

            # Add directory recursively
            #
            # @param dir_path [String] Directory path
            # @param base_path [String, nil] Base path for relative names
            # @return [void]
            def add_directory(dir_path, base_path = nil)
              base_path ||= dir_path

              Dir.glob(File.join(dir_path, "**", "*")).each do |path|
                next unless File.file?(path)

                relative_path = path.sub(
                  /^#{Regexp.escape(base_path)}#{File::SEPARATOR}?/, ""
                )
                add_file(path, relative_path)
              end
            end

            # Create multi-volume archives
            #
            # @return [Array<String>] Paths to created volume files
            def create_volumes
              # Prepare file entries with compression
              prepared_files = prepare_files

              # Calculate file distribution across volumes
              splitter = VolumeSplitter.new(max_volume_size: @volume_options.max_volume_size)
              distribution = splitter.calculate_file_distribution(prepared_files)

              # Create each volume
              volume_paths = []
              distribution.each_with_index do |file_indices, volume_idx|
                volume_number = volume_idx + 1
                is_last = (volume_idx == distribution.size - 1)

                volume_path = VolumeWriter.volume_filename(
                  @base_path,
                  volume_number,
                  naming: @volume_options.volume_naming,
                )

                write_volume(volume_path, volume_number, file_indices,
                             prepared_files, is_last)
                volume_paths << volume_path
              end

              volume_paths
            end

            # Check if archive needs splitting
            #
            # @return [Boolean] true if multi-volume needed
            def needs_splitting?
              total_size = estimate_total_size
              VolumeSplitter.needs_splitting?(total_size,
                                              @volume_options.max_volume_size)
            end

            private

            # Prepare files with compression and metadata
            #
            # @return [Array<Hash>] Prepared file information
            def prepare_files
              @files.map do |file|
                # Read and compress file data
                data = File.binread(file[:input])
                compression_method = select_compression_method(data)
                compressed_data = compress_data(data, compression_method)

                # Calculate CRC32 if needed
                use_crc32 = @compression_options[:include_crc32] && compression_method == Compression::Store::METHOD
                file_crc32 = use_crc32 ? CRC32.calculate(data) : nil

                # Create file header
                header = FileHeader.new(
                  filename: file[:archive],
                  file_size: data.bytesize,
                  compressed_size: compressed_data.bytesize,
                  compression_method: compression_method,
                  mtime: @compression_options[:include_mtime] ? file[:mtime] : nil,
                  crc32: file_crc32,
                )

                # Estimate header size (approximate)
                header_data = header.encode
                header_size = header_data.bytesize

                {
                  file: file,
                  header: header,
                  header_size: header_size,
                  compressed_data: compressed_data,
                  compressed_size: compressed_data.bytesize,
                }
              end
            end

            # Write single volume file
            #
            # @param volume_path [String] Volume file path
            # @param volume_number [Integer] Volume number (1-based)
            # @param file_indices [Array<Integer>] File indices to include
            # @param prepared_files [Array<Hash>] All prepared files
            # @param is_last [Boolean] Is this the last volume?
            # @return [void]
            def write_volume(volume_path, volume_number, file_indices,
prepared_files, is_last)
              writer = VolumeWriter.new(volume_path,
                                        volume_number: volume_number, is_last: is_last)

              writer.write do |vol|
                vol.write_signature
                vol.write_main_header

                file_indices.each do |idx|
                  prepared = prepared_files[idx]
                  vol.write_file_data(prepared[:header],
                                      prepared[:compressed_data])
                end

                vol.write_end_header
              end
            end

            # Select compression method
            #
            # @param data [String] File data
            # @return [Integer] Compression method ID
            def select_compression_method(data)
              case @compression_options[:compression]
              when :store
                Compression::Store::METHOD
              when :lzma
                level = @compression_options[:level] || 3
                Compression::Lzma.method_id(level)
              when :auto
                if data.bytesize < 1024
                  Compression::Store::METHOD
                else
                  level = @compression_options[:level] || 3
                  Compression::Lzma.method_id(level)
                end
              else
                Compression::Store::METHOD
              end
            end

            # Compress data
            #
            # @param data [String] Data to compress
            # @param method [Integer] Compression method ID
            # @return [String] Compressed data
            def compress_data(data, method)
              if method == Compression::Store::METHOD
                Compression::Store.compress(data)
              else
                level = method.clamp(1, 5)
                Compression::Lzma.compress(data, level: level)
              end
            end

            # Estimate total archive size
            #
            # @return [Integer] Estimated size in bytes
            def estimate_total_size
              # Rough estimate: sum of file sizes + overhead
              file_sizes = @files.sum { |f| f[:size] }
              overhead = 1024 * @files.size # Header overhead per file
              file_sizes + overhead
            end
          end
        end
      end
    end
  end
end
