# frozen_string_literal: true

require "fileutils"
require "zlib"
require "stringio"
require "tmpdir"

module Omnizip
  module Formats
    module Rar
      # Pure Ruby RAR archive writer
      #
      # Writes RAR 1.5-4.x ("RAR4") archives per the on-disk layout
      # unrar accepts: HEAD_CRC holds the low 16 bits of a CRC32 over
      # the header bytes that follow it, HEAD_SIZE counts the whole
      # block including the CRC field, and the 7-byte signature is
      # itself the marker block (no second marker follows).
      #
      # Only METHOD_STORE output is interoperable with official RAR
      # tools; the LZ/PPMd encoders produce Omnizip-internal streams
      # that Omnizip can read back but unrar cannot.
      #
      # @example Create a RAR archive
      #   writer = Writer.new('archive.rar')
      #   writer.add_file('document.pdf')
      #   writer.add_directory('photos/')
      #   writer.write
      #
      # @example Create with options
      #   writer = Writer.new('archive.rar',
      #     compression: :best
      #   )
      class Writer
        include Omnizip::Formats::Rar::Constants

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
        #   (not implemented; ignored with a warning)
        # @option options [Integer] :recovery Recovery record
        #   percentage (not implemented; ignored with a warning)
        # @option options [String] :password Archive password
        #   (RAR4 encryption is not implemented)
        # @option options [Integer] :volume_size Split into volumes
        #   (not implemented; ignored with a warning)
        # @option options [Boolean] :test_after_create Test archive after creation
        # @raise [NotImplementedError] if :password or :encrypt_headers is given
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = default_options.merge(options)
          @files = []
          @directories = []

          if @options[:password] || @options[:encrypt_headers]
            raise NotImplementedError,
                  "RAR4 encryption is not implemented"
          end

          warn_unimplemented_options
        end

        # Add a name-only directory entry (empty trees survive
        # archive creation instead of vanishing)
        #
        # @param archive_path [String] Directory path inside the
        #   archive (trailing slash optional)
        # @return [self]
        def add_directory_entry(archive_path)
          @files << {
            source: nil,
            archive_path: archive_path.chomp("/"),
            directory: true,
          }
          self
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
            write_archive_header(io)
            write_file_entries(io)
            write_end_block(io)
          end

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

        # Warn about accepted-but-unimplemented options so the
        # resulting archive never advertises features it lacks.
        def warn_unimplemented_options
          if @options[:solid]
            warn "RAR4 writer ignores solid: not implemented " \
                 "(no corresponding flag is written)"
          end
          if @options[:volume_size]
            warn "RAR4 writer ignores volume_size: not implemented " \
                 "(no corresponding flag is written)"
          end
          recovery = @options[:recovery]
          return unless recovery.is_a?(Numeric) && recovery.positive?
          return if recovery == true

          warn "RAR4 writer ignores recovery: not implemented " \
               "(no corresponding flag is written)"
        end

        # RAR4 HEAD_CRC: low 16 bits of the CRC32 over every header
        # byte that follows the 2-byte CRC field (unrar archive.cpp).
        #
        # @param header_data [String] Header bytes after the CRC field
        # @return [Integer] 16-bit CRC value
        def calculate_header_crc(header_data)
          Zlib.crc32(header_data) & 0xFFFF
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

        # Write RAR signature (the marker block itself)
        #
        # @param io [IO] Output stream
        def write_signature(io)
          io.write(RAR4_SIGNATURE.pack("C*"))
        end

        # Write archive header (MAIN_HEAD, 13 bytes total)
        #
        # @param io [IO] Output stream
        def write_archive_header(io)
          header_data = [BLOCK_ARCHIVE].pack("C") +
            [0x0000].pack("v") +                       # HEAD_FLAGS
            [0x000D].pack("v") +                       # HEAD_SIZE
            [0].pack("v") + [0].pack("V")              # HighPosAV, PosAV

          io.write([calculate_header_crc(header_data)].pack("v"))
          io.write(header_data)
        end

        # Write file entries
        #
        # @param io [IO] Output stream
        def write_file_entries(io)
          @directories.each do |dir_info|
            write_directory_entries(io, dir_info)
          end
          @files.each do |file_info|
            write_file_entry(io, file_info)
          end
        end

        # Write a single file entry
        #
        # @param io [IO] Output stream
        # @param file_info [Hash] File information
        def write_file_entry(io, file_info)
          file_path = file_info[:source]
          archive_path = file_info[:archive_path] || File.basename(file_path)
          directory = file_info[:directory] || false

          file_data = directory ? "" : File.binread(file_path)

          method = file_info[:method] ||
            (directory ? METHOD_STORE : select_compression_method(file_data))
          compressed_data = compress_data(file_data, method)

          if directory && file_path.nil?
            # Name-only directory entry: no source to stat
            file_attr = 0o040755
            file_time = dos_time(Time.now)
            data_crc = 0
          else
            stat = File.stat(file_path)
            file_attr = directory ? 0o040755 : stat.mode
            file_time = dos_time(stat.mtime)
            data_crc = Zlib.crc32(file_data)
          end

          name_bytes = archive_path.encode("UTF-8").bytes

          # HEAD_FLAGS bit 0x8000 (LONG_BLOCK) marks a data area of
          # PACK_SIZE bytes; the full dictionary mask 0xE0 marks
          # directory entries (a directory has no dictionary) —
          # confirmed against unrar extraction behavior.
          flags = BLOCK_LONG
          flags |= FILE_DIRECTORY if directory
          flags |= FILE_LARGE if file_data.bytesize > 0xFFFFFFFF

          # Fixed fields after HEAD_SIZE: PACK(4) + UNP(4) + HOST_OS(1)
          # + FILE_CRC(4) + FTIME(4) + UNP_VER(1) + METHOD(1) +
          # NAME_SIZE(2) + ATTR(4) = 25 bytes; plus TYPE(1) +
          # FLAGS(2) + SIZE(2) and the 2-byte CRC itself.
          header_size = 32 + name_bytes.size
          header_size += 8 if flags.anybits?(FILE_LARGE)

          header_data = [BLOCK_FILE].pack("C") +
            [flags].pack("v") +
            [header_size].pack("v") +
            [compressed_data.bytesize & 0xFFFFFFFF].pack("V") +
            [file_data.bytesize & 0xFFFFFFFF].pack("V") +
            [OS_UNIX].pack("C") +
            [data_crc].pack("V") +
            [file_time].pack("V") +
            [compression_version(method)].pack("C") +
            [method].pack("C") +
            [name_bytes.size].pack("v") +
            [file_attr].pack("V")

          if flags.anybits?(FILE_LARGE)
            header_data += [(compressed_data.bytesize >> 32) & 0xFFFFFFFF].pack("V")
            header_data += [(file_data.bytesize >> 32) & 0xFFFFFFFF].pack("V")
          end

          header_data += name_bytes.pack("C*")

          io.write([calculate_header_crc(header_data)].pack("v"))
          io.write(header_data)
          io.write(compressed_data)
        end

        # Write directory tree as explicit directory entries plus the
        # files inside them
        #
        # @param io [IO] Output stream
        # @param dir_info [Hash] Directory information
        def write_directory_entries(io, dir_info)
          dir_path = dir_info[:source]
          prefix = dir_info[:archive_path].to_s.gsub(%r{^/+|/+$}, "")

          pattern = dir_info[:recursive] ? File.join(dir_path, "**", "*") : File.join(dir_path, "*")
          Dir.glob(pattern).each do |path|
            relative = path.delete_prefix("#{dir_path}/")
            name = prefix.empty? ? relative : "#{prefix}/#{relative}"

            if File.directory?(path)
              write_file_entry(io, {
                                 source: path,
                                 archive_path: name,
                                 directory: true,
                               })
            else
              write_file_entry(io, {
                                 source: path,
                                 archive_path: name,
                               })
            end
          end
        end

        # Write end block (ENDARC, 7 bytes total)
        #
        # @param io [IO] Output stream
        def write_end_block(io)
          header_data = [BLOCK_ENDARC].pack("C") +
            [0x0000].pack("v") +
            [0x0007].pack("v")

          io.write([calculate_header_crc(header_data)].pack("v"))
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

        # Get compression version needed to extract. WinRAR writes 20
        # for stored files and 29 for every compressed method,
        # including PPMd (method 0x35) — confirmed against libarchive
        # RAR4 fixtures created by the official tool.
        #
        # @param method [Integer] Compression method
        # @return [Integer] Version code
        def compression_version(method)
          method == METHOD_STORE ? 20 : 29
        end

        # Test archive integrity by reading it back with the RAR
        # reader and comparing every extracted entry to its source
        #
        # @return [Boolean] true if valid
        def test_archive
          return false unless File.exist?(@output_path)

          reader = Reader.new(@output_path)
          reader.open

          Dir.mktmpdir("omnizip_rar_test") do |tmp|
            @files.map { |f| f[:archive_path] || File.basename(f[:source]) }
              .zip(@files.map { |f| f[:source] }).all? do |name, source|
              dest = File.join(tmp, name)
              reader.extract_entry(name, dest)
              FileUtils.compare_file(source, dest)
            end
          end
        rescue StandardError
          false
        end
      end
    end
  end
end
