# frozen_string_literal: true

require "fileutils"
require "zlib"
require "stringio"
require_relative "constants"
require_relative "header"
require_relative "compression/dispatcher"

module Omnizip
  module Formats
    module Rar
      # Pure Ruby RAR archive writer
      #
      # This class provides basic RAR archive creation in pure Ruby.
      # It writes RAR4-compatible archives with basic compression support.
      #
      # @example Create a RAR archive
      #   writer = Writer.new('archive.rar')
      #   writer.add_file('document.pdf')
      #   writer.add_directory('photos/')
      #   writer.write
      #
      # @example Create with options
      #   writer = Writer.new('archive.rar',
      #     compression: :best,
      #     solid: true,
      #     recovery: 5
      #   )
      class Writer
        include Constants

        # @return [String] Output archive path
        attr_reader :output_path

        # @return [Hash] Compression options
        attr_reader :options

        # @return [Array<Hash>] Files to add
        attr_reader :files

        # @return [Array<Hash>] Directories to add
        attr_reader :directories

        # Check if RAR creation is available
        #
        # @return [Boolean] always true for pure Ruby implementation
        def self.available?
          true
        end

        # Get RAR writer information
        #
        # @return [Hash] Writer type and version
        def self.info
          {
            available: true,
            type: :pure_ruby,
            version: "4.0",
          }
        end

        # Initialize RAR writer
        #
        # @param output_path [String] Output RAR file path
        # @param options [Hash] Compression options
        # @option options [Symbol] :compression Compression level
        #   (:store, :fastest, :fast, :normal, :good, :best)
        # @option options [Boolean] :solid Create solid archive
        # @option options [Integer] :recovery Recovery record percentage (0-10)
        # @option options [Boolean] :encrypt_headers Encrypt file names
        # @option options [String] :password Archive password
        # @option options [Integer] :volume_size Split into volumes (bytes)
        # @option options [Boolean] :test_after_create Test archive after creation
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = default_options.merge(options)
          @files = []
          @directories = []
        end

        # Add file to archive
        #
        # @param file_path [String] Path to file
        # @param archive_path [String, nil] Path within archive
        # @raise [ArgumentError] if file does not exist
        def add_file(file_path, archive_path = nil)
          raise ArgumentError, "File not found: #{file_path}" unless
            File.exist?(file_path)

          @files << {
            source: File.expand_path(file_path),
            archive_path: archive_path,
          }
        end

        # Add directory to archive
        #
        # @param dir_path [String] Path to directory
        # @param recursive [Boolean] Include subdirectories
        # @param archive_path [String, nil] Path within archive
        # @raise [ArgumentError] if directory does not exist
        def add_directory(dir_path, recursive: true, archive_path: nil)
          raise ArgumentError, "Directory not found: #{dir_path}" unless
            Dir.exist?(dir_path)

          @directories << {
            source: File.expand_path(dir_path),
            recursive: recursive,
            archive_path: archive_path,
          }
        end

        # Create RAR archive
        #
        # @return [String] Path to created archive
        def write
          File.open(@output_path, "wb") do |io|
            write_signature(io)
            write_marker_block(io)
            write_archive_header(io)
            write_file_entries(io)
            write_end_block(io)
          end

          # Test archive if requested
          test_archive if @options[:test_after_create]

          @output_path
        end

        private

        # Default compression options
        #
        # @return [Hash] Default options
        def default_options
          {
            compression: :normal,
            solid: false,
            recovery: 0,
            encrypt_headers: false,
            password: nil,
            volume_size: nil,
            test_after_create: false,
          }
        end

        # Calculate CRC16-CCITT for block headers
        #
        # RAR uses CRC16-CCITT with polynomial 0x1021
        # @param data [String] Header data to checksum
        # @return [Integer] 16-bit CRC value
        def calculate_header_crc16(data)
          crc = 0
          data.bytes.each do |byte|
            crc ^= (byte << 8)
            8.times do
              crc = crc.anybits?(0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1)
            end
          end
          crc & 0xFFFF
        end

        # Convert Ruby Time to DOS time format
        #
        # @param time [Time] Ruby time object
        # @return [Integer] DOS time format (32-bit)
        def dos_time(time)
          dos_date = ((time.year - 1980) << 9) | (time.month << 5) | time.day
          dos_time_part = (time.hour << 11) | (time.min << 5) | (time.sec / 2)
          (dos_date << 16) | dos_time_part
        end

        # Write RAR signature
        #
        # @param io [IO] Output stream
        def write_signature(io)
          io.write(RAR4_SIGNATURE.pack("C*"))
        end

        # Write marker block
        #
        # @param io [IO] Output stream
        def write_marker_block(io)
          # Marker block has fixed CRC of 0x6152
          io.write([0x6152].pack("v")) # HEAD_CRC
          io.write([BLOCK_MARKER].pack("C")) # HEAD_TYPE
          io.write([0x0000].pack("v"))      # HEAD_FLAGS
          io.write([0x0007].pack("v"))      # HEAD_SIZE
        end

        # Write archive header
        #
        # @param io [IO] Output stream
        def write_archive_header(io)
          flags = 0
          flags |= ARCHIVE_SOLID if @options[:solid]
          flags |= ARCHIVE_RECOVERY if @options[:recovery].positive?
          flags |= ARCHIVE_ENCRYPTED if @options[:password]
          flags |= ARCHIVE_VOLUME if @options[:volume_size]

          # Build header data (without CRC)
          # SIZE includes: TYPE(1) + FLAGS(2) + SIZE(2) + Reserved(6) = 11 bytes
          header_data = [BLOCK_ARCHIVE].pack("C") +
            [flags].pack("v") +
            [0x000B].pack("v") +
            [0, 0, 0].pack("vvv") # 6 bytes reserved (3 x uint16)

          # Calculate and write CRC
          crc = calculate_header_crc16(header_data)
          io.write([crc].pack("v"))
          io.write(header_data)
        end

        # Write file entries
        #
        # @param io [IO] Output stream
        def write_file_entries(io)
          @files.each do |file_info|
            write_file_entry(io, file_info)
          end

          @directories.each do |dir_info|
            write_directory_entries(io, dir_info)
          end
        end

        # Write a single file entry
        #
        # @param io [IO] Output stream
        # @param file_info [Hash] File information
        def write_file_entry(io, file_info)
          file_path = file_info[:source]
          archive_path = file_info[:archive_path] || File.basename(file_path)

          file_data = File.binread(file_path)

          # Select appropriate compression method based on data
          method = file_info[:method] || select_compression_method(file_data)
          compressed_data = compress_data(file_data, method)

          # File metadata
          stat = File.stat(file_path)
          file_attr = stat.mode
          file_time = dos_time(stat.mtime)
          data_crc = Zlib.crc32(file_data)

          # Name encoding
          name_bytes = archive_path.encode("UTF-8").bytes

          # Flags
          flags = FILE_UNICODE
          flags |= FILE_ENCRYPTED if @options[:password]
          flags |= FILE_LARGE if file_data.size > 0xFFFFFFFF

          # Calculate header size
          # Fixed fields: TYPE(1) + FLAGS(2) + SIZE(2) + PACK_SIZE(4) + UNPACK_SIZE(4) +
          #               HOST_OS(1) + FILE_CRC(4) + FILE_TIME(4) + VERSION(1) + METHOD(1) +
          #               NAME_SIZE(2) + ATTR(4) = 30 bytes
          header_size = 30 + name_bytes.size
          header_size += 8 if flags & FILE_LARGE != 0

          # Build file header (without CRC)
          header_data = [BLOCK_FILE].pack("C") +
            [flags].pack("v") +
            [header_size].pack("v") +
            [compressed_data.bytesize & 0xFFFFFFFF].pack("V") +
            [file_data.bytesize & 0xFFFFFFFF].pack("V") +
            [OS_UNIX].pack("C") +
            [data_crc].pack("V") +
            [file_time].pack("V") +
            [compression_version(method)].pack("C") +  # VERSION first
            [method].pack("C") +                       # METHOD second
            [name_bytes.size].pack("v") +
            [file_attr].pack("V")

          # Add high 32 bits for large files
          if flags & FILE_LARGE != 0
            header_data += [(compressed_data.bytesize >> 32) & 0xFFFFFFFF].pack("V")
            header_data += [(file_data.bytesize >> 32) & 0xFFFFFFFF].pack("V")
          end

          # Add filename
          header_data += name_bytes.pack("C*")

          # Calculate and write CRC
          crc = calculate_header_crc16(header_data)
          io.write([crc].pack("v"))
          io.write(header_data)
          io.write(compressed_data)
        end

        # Write directory entries
        #
        # @param io [IO] Output stream
        # @param dir_info [Hash] Directory information
        def write_directory_entries(io, dir_info)
          dir_path = dir_info[:source]
          recursive = dir_info[:recursive]

          pattern = recursive ? "**/*" : "*"
          Dir.glob(File.join(dir_path, pattern)).each do |path|
            next unless File.file?(path)

            relative_path = path.sub("#{dir_path}/", "")
            write_file_entry(io, {
                               source: path,
                               archive_path: relative_path,
                             })
          end
        end

        # Write end block
        #
        # @param io [IO] Output stream
        def write_end_block(io)
          flags = 0x4000 # ENDARC flag

          # Build header data (without CRC)
          header_data = [BLOCK_ENDARC].pack("C") +
            [flags].pack("v") +
            [0x0007].pack("v")

          # Calculate and write CRC
          crc = calculate_header_crc16(header_data)
          io.write([crc].pack("v"))
          io.write(header_data)
        end

        # Compress data using native RAR compression
        #
        # @param data [String] Data to compress
        # @param method [Integer] RAR compression method (default: METHOD_NORMAL)
        # @return [String] Compressed data
        def compress_data(data, method = METHOD_NORMAL)
          input = StringIO.new(data)
          output = StringIO.new

          # Use native compression dispatcher
          Compression::Dispatcher.compress(method, input, output, @options)

          output.string
        end

        # Select appropriate compression method based on data
        #
        # @param data [String] Data to compress
        # @return [Integer] RAR compression method code
        def select_compression_method(data)
          # Small files: use METHOD_STORE to avoid Huffman tree overhead (258 bytes)
          return METHOD_STORE if data.size < 300

          # User-specified compression level takes precedence
          case @options[:compression]
          when :store
            METHOD_STORE
          when :fastest
            METHOD_FASTEST
          when :fast
            METHOD_FAST
          when :normal
            METHOD_NORMAL
          when :good
            METHOD_GOOD
          when :best
            METHOD_BEST
          else
            # Default based on compression level option if numeric
            if @options[:level] == 9
              METHOD_BEST # PPMd for maximum compression
            else
              METHOD_NORMAL # LZ77+Huffman default
            end
          end
        end

        # Get Zlib compression level (DEPRECATED - kept for compatibility)
        #
        # @return [Integer] Zlib compression level
        def compression_zlib_level
          case @options[:compression]
          when :store then Zlib::NO_COMPRESSION
          when :fastest then Zlib::BEST_SPEED
          when :fast then 3
          when :normal then Zlib::DEFAULT_COMPRESSION
          when :good then 7
          when :best then Zlib::BEST_COMPRESSION
          else Zlib::DEFAULT_COMPRESSION
          end
        end

        # Get compression method code (DEPRECATED - use select_compression_method)
        #
        # @return [Integer] Method code
        def compression_method
          case @options[:compression]
          when :store then METHOD_STORE
          when :fastest then METHOD_FASTEST
          when :fast then METHOD_FAST
          when :normal then METHOD_NORMAL
          when :good then METHOD_GOOD
          when :best then METHOD_BEST
          else METHOD_NORMAL
          end
        end

        # Get compression version based on method
        #
        # @param method [Integer] Compression method
        # @return [Integer] Version code
        def compression_version(method)
          method == METHOD_STORE ? 20 : 29
        end

        # Test archive integrity
        #
        # @return [Boolean] true if valid
        def test_archive
          # Basic validation: check if file exists and has RAR signature
          return false unless File.exist?(@output_path)

          File.open(@output_path, "rb") do |io|
            signature = io.read(7)
            signature&.bytes == RAR4_SIGNATURE[0..6]
          end
        end
      end
    end
  end
end
