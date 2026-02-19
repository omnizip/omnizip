# frozen_string_literal: true

require_relative "header"
require_relative "vint"
require_relative "crc32"
require_relative "compression/store"
require_relative "compression/lzma"
require_relative "compression/lzss"
require_relative "multi_volume/volume_manager"
require_relative "models/volume_options"
require_relative "models/solid_options"
require_relative "models/encryption_options"
require_relative "models/recovery_options"
require_relative "solid/solid_manager"
require_relative "encryption/encryption_manager"
require_relative "../../../parity/par2_creator"

module Omnizip
  module Formats
    module Rar
      module Rar5
        # RAR5 format writer
        #
        # This class creates RAR5 archives with STORE or LZMA compression.
        # Supports single-file archives, multi-volume archives, solid compression,
        # AES-256-CBC encryption, and PAR2 recovery records.
        #
        # @example Create single archive with STORE compression
        #   writer = Writer.new('archive.rar')
        #   writer.add_file('test.txt')
        #   writer.write
        #
        # @example Create archive with LZMA compression
        #   writer = Writer.new('archive.rar', compression: :lzma, level: 5)
        #   writer.add_file('test.txt')
        #   writer.write
        #
        # @example Create solid archive
        #   writer = Writer.new('archive.rar', compression: :lzma, level: 5, solid: true)
        #   writer.add_directory('project/')
        #   writer.write
        #
        # @example Create encrypted archive
        #   writer = Writer.new('archive.rar',
        #     compression: :lzma,
        #     password: 'SecurePass123!',
        #     kdf_iterations: 262_144
        #   )
        #   writer.add_file('confidential.pdf')
        #   writer.write
        #
        # @example Create multi-volume archive
        #   writer = Writer.new('archive.rar',
        #     multi_volume: true,
        #     volume_size: '10M',
        #     compression: :lzma
        #   )
        #   writer.add_file('largefile.dat')
        #   writer.write  # Returns: ['archive.part1.rar', 'archive.part2.rar', ...]
        class Writer
          # RAR5 signature: "Rar!\x1A\x07\x01\x00"
          RAR5_SIGNATURE = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01,
                            0x00].pack("C*")

          # Threshold for automatic compression selection (1 KB)
          AUTO_COMPRESS_THRESHOLD = 1024

          # @return [String] Output archive path
          attr_reader :path

          # @return [Hash] Archive options
          attr_reader :options

          # Initialize RAR5 writer
          #
          # @param path [String] Output RAR file path
          # @param options [Hash] Archive options
          # @option options [Symbol] :compression Compression method (:store, :lzma, :auto)
          # @option options [Integer] :level LZMA compression level (1-5, default: 3)
          # @option options [Boolean] :include_mtime Include modification time in file headers (default: false)
          # @option options [Boolean] :include_crc32 Include CRC32 checksum in file headers (default: false)
          # @option options [Boolean] :solid Enable solid compression (default: false)
          # @option options [String] :password Password for encryption (default: nil)
          # @option options [Integer] :kdf_iterations PBKDF2 iterations for encryption (default: 262,144)
          # @option options [Boolean] :recovery Enable PAR2 recovery records (default: false)
          # @option options [Integer] :recovery_percent Redundancy percentage for PAR2 (default: 5)
          # @option options [Boolean] :multi_volume Enable multi-volume archive (default: false)
          # @option options [Integer, String] :volume_size Maximum volume size (e.g., "10M", 10485760)
          # @option options [String] :volume_naming Volume naming pattern ("part", "volume", "numeric")
          def initialize(path, options = {})
            @path = path
            @options = {
              compression: :store,
              level: 3,
              include_mtime: false,
              include_crc32: false,
              solid: false,
              password: nil,
              kdf_iterations: 262_144,
              recovery: false,
              recovery_percent: 5,
              multi_volume: false,
              volume_size: nil,
              volume_naming: "part",
            }.merge(options)
            @files = []

            # Initialize encryption manager if password provided (and not empty)
            @encryption_manager = if @options[:password] && !@options[:password].empty?
                                    Encryption::EncryptionManager.new(
                                      @options[:password],
                                      kdf_iterations: @options[:kdf_iterations],
                                    )
                                  end
          end

          # Add file to archive
          #
          # @param input_path [String] Path to file on disk
          # @param archive_path [String, nil] Path within archive (defaults to basename)
          # @raise [ArgumentError] if file does not exist
          def add_file(input_path, archive_path = nil)
            unless File.exist?(input_path)
              raise ArgumentError,
                    "File not found: #{input_path}"
            end

            archive_path ||= File.basename(input_path)

            # Store file with metadata
            @files << {
              input: input_path,
              archive: archive_path,
              mtime: File.mtime(input_path),
              stat: File.stat(input_path),
            }
          end

          # Add directory recursively
          #
          # @param dir_path [String] Directory path
          # @param base_path [String, nil] Base path for relative names
          # @return [void]
          def add_directory(dir_path, base_path = nil)
            unless File.directory?(dir_path)
              raise ArgumentError,
                    "Directory not found: #{dir_path}"
            end

            base_path ||= dir_path

            Dir.glob(File.join(dir_path, "**", "*")).each do |path|
              next unless File.file?(path)

              relative_path = path.sub(
                /^#{Regexp.escape(base_path)}#{File::SEPARATOR}?/, ""
              )
              add_file(path, relative_path)
            end
          end

          # Write archive to disk
          #
          # For single archives, returns the archive path or array of paths (with PAR2).
          # For multi-volume archives, returns an array of volume paths.
          #
          # @return [String, Array<String>] Path(s) to created archive(s) and PAR2 files
          def write
            archive_paths = if @options[:multi_volume]
                              write_multi_volume
                            else
                              write_single_archive
                              [@path]
                            end

            # Generate PAR2 recovery files if requested
            if @options[:recovery]
              par2_paths = generate_recovery_files(archive_paths)
              return archive_paths + par2_paths
            end

            @options[:multi_volume] ? archive_paths : archive_paths.first
          end

          private

          # Write single-file archive
          #
          # @return [void]
          def write_single_archive
            File.open(@path, "wb") do |f|
              write_signature(f)
              write_main_header(f)

              if @options[:solid]
                write_solid_block(f, @files)
              else
                @files.each do |file|
                  write_file_entry(f, file)
                end
              end

              write_end_header(f)
            end
          end

          # Write multi-volume archive (new behavior)
          #
          # @return [Array<String>] Paths to created volume files
          def write_multi_volume
            # Parse volume size if string
            volume_size = if @options[:volume_size].is_a?(String)
                            Models::VolumeOptions.parse_size(@options[:volume_size])
                          else
                            @options[:volume_size] || 104_857_600 # 100 MB default
                          end

            # Create volume manager
            manager = MultiVolume::VolumeManager.new(@path,
                                                     max_volume_size: volume_size,
                                                     volume_naming: @options[:volume_naming],
                                                     compression: @options[:compression],
                                                     level: @options[:level],
                                                     include_mtime: @options[:include_mtime],
                                                     include_crc32: @options[:include_crc32])

            # Add all files to manager
            @files.each do |file|
              manager.add_file(file[:input], file[:archive])
            end

            # Create volumes
            manager.create_volumes
          end

          # Write solid block containing multiple files
          #
          # @param io [IO] Output stream
          # @param files [Array<Hash>] Files to compress in solid mode
          # @return [void]
          def write_solid_block(io, files)
            # Create solid manager
            manager = Solid::SolidManager.new(level: @options[:level])

            # Add all files to solid stream
            files.each do |file|
              data = File.binread(file[:input])
              manager.add_file(file[:archive], data, mtime: file[:mtime],
                                                     stat: file[:stat])
            end

            # Compress entire solid block
            result = manager.compress_all

            # Write each file header with references to the solid block
            # In RAR5, all files share the same compressed data
            files.each_with_index do |file, idx|
              file_info = result[:files][idx]

              # Calculate CRC32 if needed (note: only for STORE in non-solid)
              # Solid compression always uses LZMA, so CRC32 is not included
              compression_method = Compression::Lzma.method_id(@options[:level])

              header = FileHeader.new(
                filename: file[:archive],
                file_size: file_info[:size],
                compressed_size: (idx.zero? ? result[:compressed_size] : 0), # Only first file has compressed size
                compression_method: compression_method,
                mtime: @options[:include_mtime] ? file[:mtime] : nil,
                crc32: nil, # No CRC32 for solid/LZMA
              )

              io.write(header.encode)
            end

            # Write the compressed data once after all headers
            io.write(result[:compressed_data])
          end

          # Write RAR5 signature (8 bytes)
          #
          # @param io [IO] Output stream
          def write_signature(io)
            io.write(RAR5_SIGNATURE)
          end

          # Write Main header
          #
          # @param io [IO] Output stream
          def write_main_header(io)
            header = MainHeader.new
            io.write(header.encode)
          end

          # Write file entry (header + data)
          #
          # @param io [IO] Output stream
          # @param file [Hash] File information
          def write_file_entry(io, file)
            # Read file data
            data = File.binread(file[:input])

            # Select compression method
            compression_method = select_compression_method(data)

            # Compress data (may return hash with properties for LZMA)
            compression_result = compress_data(data, compression_method)

            # Extract compressed data and optional properties
            if compression_result.is_a?(Hash)
              compressed_data = compression_result[:data]
              compression_properties = compression_result[:properties]
            else
              compressed_data = compression_result
              compression_properties = nil
            end

            # Build extra area if compression properties are present
            extra_area = build_compression_extra_area(compression_properties)

            # Encrypt if password provided (encryption happens AFTER compression)
            if @encryption_manager
              encryption_result = @encryption_manager.encrypt_file_data(compressed_data)
              final_data = encryption_result[:encrypted_data]
              # TODO: Store encryption_result[:header] for decryption
            else
              final_data = compressed_data
            end

            # Calculate CRC32 if needed
            # NOTE: RAR5's optional CRC32 is only compatible with STORE compression.
            # When LZMA or other compression is used, disable CRC32 even if requested.
            # When encryption is used, CRC32 is also not included.
            use_crc32 = @options[:include_crc32] &&
              compression_method == Compression::Store::METHOD &&
              !@encryption_manager
            file_crc32 = use_crc32 ? CRC32.calculate(data) : nil

            # Create file header
            header = FileHeader.new(
              filename: file[:archive],
              file_size: data.bytesize,
              compressed_size: final_data.bytesize,
              compression_method: compression_method,
              mtime: @options[:include_mtime] ? file[:mtime] : nil,
              crc32: file_crc32,
              extra_area: extra_area,
            )

            # Write header
            io.write(header.encode)

            # Write data (compressed and encrypted if applicable)
            io.write(final_data)
          end

          # Write End header
          #
          # @param io [IO] Output stream
          def write_end_header(io)
            header = EndHeader.new
            io.write(header.encode)
          end

          # Select compression method based on options and data
          #
          # @param data [String] File data
          # @return [Integer] Compression method ID
          def select_compression_method(data)
            case @options[:compression]
            when :store
              Compression::Store::METHOD
            when :lzss, :lzma
              # RAR5 uses LZSS compression (methods 1-5)
              # Note: :lzma is deprecated, use :lzss for clarity
              level = @options[:level] || 3
              if Compression::Lzss.available?
                Compression::Lzss.method_id(level)
              else
                # LZSS not implemented, fall back to STORE
                Compression::Store::METHOD
              end
            when :auto
              # Auto-select based on file size
              if data.bytesize < AUTO_COMPRESS_THRESHOLD
                Compression::Store::METHOD
              else
                level = @options[:level] || 3
                if Compression::Lzss.available?
                  Compression::Lzss.method_id(level)
                else
                  # LZSS not implemented, fall back to STORE
                  Compression::Store::METHOD
                end
              end
            else
              Compression::Store::METHOD
            end
          end

          # Compress data using selected method
          #
          # @param data [String] Data to compress
          # @param method [Integer] Compression method ID
          # @return [String, Hash] Compressed data or hash with :data and :properties
          def compress_data(data, method)
            if method == Compression::Store::METHOD
              Compression::Store.compress(data)
            else
              # Methods 1-5 are RAR5 LZSS with different levels
              level = method.clamp(1, 5)
              if Compression::Lzss.available?
                Compression::Lzss.compress(data, level: level)
              else
                # LZSS not implemented, fall back to STORE
                Compression::Store.compress(data)
              end
            end
          end

          # Build extra area for compression parameters
          #
          # RAR5 stores compression parameters in an extra area with type 0x03.
          # The format depends on the compression method used.
          #
          # @param properties [String, nil] Compression properties
          # @return [String, nil] Encoded extra area or nil if no properties
          def build_compression_extra_area(properties)
            return nil if properties.nil?

            extra_data = []

            # Extra record type: 0x03 = Compression parameters
            extra_data.concat(VINT.encode(0x03))

            # Compression properties (method-specific)
            extra_data.concat(properties.bytes)

            extra_data.pack("C*")
          end

          # Generate PAR2 recovery files for archives
          #
          # @param archive_paths [Array<String>] Paths to archive files
          # @return [Array<String>] Paths to created PAR2 files
          def generate_recovery_files(archive_paths)
            base_name = @path.sub(/\.rar$/, "")

            creator = Parity::Par2Creator.new(
              redundancy: @options[:recovery_percent] || 5,
              block_size: 16_384,
            )

            # Add all archive files
            archive_paths.each do |path|
              creator.add_file(path)
            end

            # Create PAR2 files
            creator.create(base_name)
          end
        end
      end
    end
  end
end
