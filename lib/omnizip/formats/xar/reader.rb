# frozen_string_literal: true

require "zlib"
require "digest"
require_relative "constants"
require_relative "header"
require_relative "toc"
require_relative "entry"

module Omnizip
  module Formats
    module Xar
      # XAR archive reader
      #
      # Provides read access to XAR archives with support for:
      # - Multiple compression algorithms (gzip, bzip2, lzma, xz, none)
      # - Checksum verification
      # - Extended attributes
      # - Hardlinks and symlinks
      class Reader
        include Constants

        attr_reader :file_path, :header, :toc, :entries

        # Open a XAR archive for reading
        #
        # @param file_path [String] Path to XAR file
        # @return [Reader] Reader instance
        def self.open(file_path)
          reader = new(file_path)
          reader.open

          if block_given?
            begin
              yield reader
            ensure
              reader.close
            end
          else
            reader
          end
        end

        # Read and list entries from XAR archive
        #
        # @param file_path [String] Path to XAR file
        # @return [Array<Entry>] List of entries
        def self.list(file_path)
          open(file_path, &:entries) # rubocop:disable Security/Open
        end

        # Extract XAR archive to directory
        #
        # @param file_path [String] Path to XAR file
        # @param output_dir [String] Output directory
        def self.extract(file_path, output_dir)
          open(file_path) do |reader| # rubocop:disable Security/Open
            reader.extract_all(output_dir)
          end
        end

        # Initialize reader
        #
        # @param file_path [String] Path to XAR file
        def initialize(file_path)
          @file_path = file_path
          @file = nil
          @header = nil
          @toc = nil
          @entries = []
          @heap_offset = 0
        end

        # Open and parse the archive
        #
        # @return [Reader] self
        def open
          @file = File.open(@file_path, "rb")
          read_header
          read_toc
          self
        end

        # Close the archive
        def close
          @file&.close
          @file = nil
        end

        # Check if archive is open
        #
        # @return [Boolean] true if open
        def open?
          !@file.nil?
        end

        # Get all entries
        #
        # @return [Array<Entry>] List of entries
        def list
          @entries
        end

        # Get entry by name
        #
        # @param name [String] Entry name
        # @return [Entry, nil] Entry or nil if not found
        def get_entry(name)
          @entries.find { |e| e.name == name }
        end

        # Read entry data
        #
        # @param entry [Entry] Entry to read
        # @return [String, nil] Entry data or nil if no data
        def read_data(entry)
          return nil unless entry.data_length&.positive?
          return nil unless @file

          @file.seek(@heap_offset + entry.data_offset)
          # In XAR format:
          # - data_length is the compressed (archived) size (what to read from heap)
          # - data_size is the uncompressed (extracted) size (decompressed size)
          compressed_data = @file.read(entry.data_length)

          decompress_data(compressed_data, entry.data_encoding, entry.data_size)
        end

        # Extract all entries to directory
        #
        # @param output_dir [String] Output directory
        def extract_all(output_dir)
          FileUtils.mkdir_p(output_dir)

          # Sort entries to ensure directories are created first
          sorted_entries = @entries.sort_by do |e|
            [e.directory? ? 0 : 1, e.name]
          end

          sorted_entries.each do |entry|
            extract_entry(entry, output_dir)
          end
        end

        # Extract single entry to directory
        #
        # @param entry [Entry] Entry to extract
        # @param output_dir [String] Output directory
        def extract_entry(entry, output_dir)
          full_path = File.join(output_dir, entry.name)

          case entry.type
          when TYPE_DIRECTORY
            FileUtils.mkdir_p(full_path)
          when TYPE_SYMLINK
            extract_symlink(entry, full_path)
          when TYPE_HARDLINK
            extract_hardlink(entry, full_path, output_dir)
          when TYPE_FILE
            extract_file(entry, full_path)
          when TYPE_BLOCK, TYPE_CHAR
            extract_device(entry, full_path)
          when TYPE_FIFO
            extract_fifo(entry, full_path)
          else
            # Unknown type, try to extract as file
            extract_file(entry, full_path) if entry.data_size&.positive?
          end

          # Set file metadata
          set_entry_metadata(entry, full_path)
        end

        # Get archive information
        #
        # @return [Hash] Archive info
        def info
          {
            file_path: @file_path,
            header: {
              version: @header&.version,
              checksum_algorithm: @header&.checksum_algorithm_name,
              toc_compressed_size: @header&.toc_compressed_size,
              toc_uncompressed_size: @header&.toc_uncompressed_size,
            },
            entry_count: @entries.size,
            file_count: @entries.count(&:file?),
            directory_count: @entries.count(&:directory?),
            symlink_count: @entries.count(&:symlink?),
            total_size: @entries.sum { |e| e.size || 0 },
          }
        end

        private

        # Read and parse header
        def read_header
          @header = Header.read(@file)
          @header.validate!
        end

        # Read and parse TOC
        def read_toc
          # Read compressed TOC
          @file.seek(@header.header_size)
          compressed_toc = @file.read(@header.toc_compressed_size)

          raise "Failed to read TOC" unless compressed_toc

          # Parse TOC
          @toc = Toc.parse(compressed_toc, @header.toc_uncompressed_size)
          @entries = @toc.entries

          # Calculate heap offset:
          # header + compressed TOC + TOC checksum
          # The TOC checksum size comes from the header's checksum algorithm
          toc_checksum_size = @header.checksum_size
          @heap_offset = @header.header_size + @header.toc_compressed_size + toc_checksum_size
        end

        # Decompress data based on encoding
        #
        # @param data [String] Compressed data
        # @param encoding [String] Compression encoding
        # @param expected_size [Integer] Expected decompressed size
        # @return [String] Decompressed data
        def decompress_data(data, encoding, _expected_size = nil)
          case encoding
          when COMPRESSION_GZIP, "application/x-gzip"
            decompress_gzip(data)
          when COMPRESSION_BZIP2, "application/x-bzip2"
            decompress_bzip2(data)
          when COMPRESSION_LZMA, "application/x-lzma"
            decompress_lzma(data)
          when COMPRESSION_XZ, "application/x-xz"
            decompress_xz(data)
          else
            # No compression or unknown
            data || +""
          end
        end

        # Decompress gzip data
        #
        # @param data [String] Zlib compressed data (XAR uses zlib, not actual gzip)
        # @return [String] Decompressed data
        def decompress_gzip(data)
          # XAR "gzip" compression is actually zlib format (with 0x78xx header)
          # Try different decompression methods for robustness

          # Method 1: Standard zlib format (with header)
          begin
            result = Zlib::Inflate.inflate(data)
            return result
          rescue Zlib::Error
            # Continue to next method
          end

          # Method 2: Raw deflate (some implementations may use this)
          begin
            inf = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            result = inf.inflate(data)
            inf.finish
            inf.close
            return result
          rescue Zlib::Error
            # Continue to next method
          end

          # Method 3: Raw deflate without finish (for truncated data)
          begin
            inf = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            result = inf.inflate(data)
            inf.close
            result
          rescue Zlib::Error => e
            raise "Failed to decompress data: #{e.message}"
          end
        end

        # Decompress bzip2 data
        #
        # @param data [String] Bzip2 compressed data
        # @return [String] Decompressed data
        def decompress_bzip2(data)
          require_relative "../../algorithms/bzip2/decompressor"
          decompressor = Omnizip::Algorithms::Bzip2::Decompressor.new
          decompressor.decompress(data)
        end

        # Decompress LZMA data
        #
        # @param data [String] LZMA compressed data
        # @return [String] Decompressed data
        def decompress_lzma(data)
          require_relative "../../algorithms/lzma/decoder"
          decoder = Omnizip::Algorithms::Lzma::Decoder.new
          decoder.decode(data)
        end

        # Decompress XZ data
        #
        # @param data [String] XZ compressed data
        # @return [String] Decompressed data
        def decompress_xz(data)
          require_relative "../xz"
          reader = Omnizip::Formats::Xz::StreamReader.new(StringIO.new(data))
          reader.read
        ensure
          reader&.close
        end

        # Extract file
        #
        # @param entry [Entry] File entry
        # @param path [String] Output path
        def extract_file(entry, path)
          FileUtils.mkdir_p(File.dirname(path))

          data = read_data(entry)
          return unless data

          File.binwrite(path, data)
        end

        # Extract symlink
        #
        # @param entry [Entry] Symlink entry
        # @param path [String] Output path
        def extract_symlink(entry, path)
          FileUtils.mkdir_p(File.dirname(path))

          target = entry.link_target
          return unless target

          File.unlink(path) if File.symlink?(path)
          File.symlink(target, path)
        end

        # Extract hardlink
        #
        # @param entry [Entry] Hardlink entry
        # @param path [String] Output path
        # @param output_dir [String] Output directory
        def extract_hardlink(entry, path, output_dir)
          FileUtils.mkdir_p(File.dirname(path))

          target = entry.link_target
          return unless target

          target_path = File.join(output_dir, target)

          # If target exists, create hardlink
          if File.exist?(target_path)
            FileUtils.rm_f(path)
            File.link(target_path, path)
          end
        end

        # Extract device node
        #
        # @param entry [Entry] Device entry
        # @param path [String] Output path
        def extract_device(entry, path)
          # Creating device nodes requires root privileges
          # This is a no-op on most systems
        end

        # Extract FIFO
        #
        # @param entry [Entry] FIFO entry
        # @param path [String] Output path
        def extract_fifo(entry, path)
          # Creating FIFOs may require privileges
          # This is a no-op on most systems
        end

        # Set entry metadata on extracted file
        #
        # @param entry [Entry] Entry
        # @param path [String] File path
        def set_entry_metadata(entry, path)
          return unless File.exist?(path)

          # Set mode
          File.chmod(entry.mode, path) if entry.mode&.positive?

          # Set timestamps
          if entry.mtime
            File.utime(entry.atime || entry.mtime, entry.mtime, path)
          end

          # Set ownership (requires privileges)
          if entry.uid && entry.gid
            begin
              File.chown(entry.uid, entry.gid, path)
            rescue Errno::EPERM
              # Ignore permission errors
            end
          end
        end
      end
    end
  end
end
