# frozen_string_literal: true

require "zlib"
require "digest"
require "fileutils"
require_relative "constants"
require_relative "header"
require_relative "toc"
require_relative "entry"

module Omnizip
  module Formats
    module Xar
      # XAR archive writer
      #
      # Provides write access to create XAR archives with support for:
      # - Multiple compression algorithms (gzip, bzip2, lzma, xz, none)
      # - Checksum generation (md5, sha1, sha256, etc.)
      # - Extended attributes
      # - Hardlinks and symlinks
      class Writer
        include Constants

        attr_reader :output_path, :entries, :options

        # Create a XAR archive
        #
        # @param output_path [String] Path to output file
        # @param options [Hash] Archive options
        # @yield [Writer] Writer instance for adding files
        # @return [String] Path to created archive
        def self.create(output_path, options = {})
          writer = new(output_path, options)

          yield writer if block_given?

          writer.write
          output_path
        end

        # Initialize writer
        #
        # @param output_path [String] Path to output file
        # @param options [Hash] Archive options
        # @option options [String] :compression Compression algorithm (gzip, bzip2, lzma, xz, none)
        # @option options [Integer] :compression_level Compression level (1-9)
        # @option options [String] :toc_checksum TOC checksum algorithm (sha1, md5, sha256)
        # @option options [String] :file_checksum File checksum algorithm (sha1, md5, sha256)
        def initialize(output_path, options = {})
          @output_path = output_path
          @options = {
            compression: DEFAULT_COMPRESSION,
            compression_level: DEFAULT_COMPRESSION_LEVEL,
            toc_checksum: DEFAULT_TOC_CHECKSUM,
            file_checksum: DEFAULT_FILE_CHECKSUM,
          }.merge(options)

          @entries = []
          @heap_data = +""
          @next_id = 1
          @hardlinks = {} # inode -> entry mapping for hardlink detection
        end

        # Add file to archive
        #
        # @param path [String] File path (on disk)
        # @param archive_path [String, nil] Path in archive (defaults to basename)
        # @return [Entry] Added entry
        def add_file(path, archive_path = nil)
          archive_path ||= File.basename(path)
          stat = File.stat(path)

          entry = Entry.new(archive_path, {
                              type: TYPE_FILE,
                              mode: stat.mode & 0o7777,
                              uid: stat.uid,
                              gid: stat.gid,
                              size: stat.size,
                              mtime: stat.mtime,
                              atime: stat.atime,
                              ctime: stat.ctime.respond_to?(:to_time) ? stat.ctime.to_time : stat.ctime,
                            })

          # Check for hardlink
          if stat.nlink > 1
            inode_key = "#{stat.dev}:#{stat.ino}"
            if (existing = @hardlinks[inode_key])
              # Create hardlink entry instead
              entry.type = TYPE_HARDLINK
              entry.link_type = "hard"
              entry.link_target = existing.name
              entry.nlink = stat.nlink
            else
              @hardlinks[inode_key] = entry
              read_and_add_file_data(entry, path)
            end
          else
            read_and_add_file_data(entry, path)
          end

          add_entry(entry)
        end

        # Add directory to archive
        #
        # @param path [String] Directory path (on disk)
        # @param archive_path [String, nil] Path in archive
        # @return [Entry] Added entry
        def add_directory(path, archive_path = nil)
          archive_path ||= File.basename(path)
          stat = File.stat(path)

          entry = Entry.new(archive_path, {
                              type: TYPE_DIRECTORY,
                              mode: stat.mode & 0o7777,
                              uid: stat.uid,
                              gid: stat.gid,
                              mtime: stat.mtime,
                              atime: stat.atime,
                              ctime: stat.ctime.respond_to?(:to_time) ? stat.ctime.to_time : stat.ctime,
                            })

          add_entry(entry)
        end

        # Add symlink to archive
        #
        # @param path [String] Symlink path (on disk)
        # @param archive_path [String, nil] Path in archive
        # @return [Entry] Added entry
        def add_symlink(path, archive_path = nil)
          archive_path ||= File.basename(path)
          stat = File.lstat(path)

          entry = Entry.new(archive_path, {
                              type: TYPE_SYMLINK,
                              mode: stat.mode & 0o7777,
                              uid: stat.uid,
                              gid: stat.gid,
                              mtime: stat.mtime,
                              atime: stat.atime,
                              link_type: "symbolic",
                              link_target: File.readlink(path),
                            })

          add_entry(entry)
        end

        # Add entry from data
        #
        # @param archive_path [String] Path in archive
        # @param data [String] File data
        # @param options [Hash] Entry options
        # @return [Entry] Added entry
        def add_data(archive_path, data, options = {})
          entry = Entry.new(archive_path, {
                              type: TYPE_FILE,
                              mode: options[:mode] || 0o644,
                              mtime: options[:mtime] || Time.now,
                              atime: options[:atime] || Time.now,
                              **options,
                            })

          entry.data = data
          compress_and_add_entry_data(entry, data)
          add_entry(entry)
        end

        # Add entry to archive
        #
        # @param entry [Entry] Entry to add
        # @return [Entry] Added entry
        def add_entry(entry)
          entry.id ||= @next_id
          @next_id = [@next_id, entry.id + 1].max
          @entries << entry
          entry
        end

        # Add tree (directory recursively) to archive
        #
        # @param path [String] Root directory path
        # @param archive_path [String, nil] Base path in archive
        def add_tree(path, archive_path = nil)
          stat = File.lstat(path)

          if stat.symlink?
            add_symlink(path, archive_path)
          elsif stat.directory?
            add_directory(path, archive_path)

            Dir.foreach(path) do |entry|
              next if [".", ".."].include?(entry)

              child_path = File.join(path, entry)
              child_archive_path = archive_path ? File.join(archive_path, entry) : entry
              add_tree(child_path, child_archive_path)
            end
          else
            add_file(path, archive_path)
          end
        end

        # Write archive to disk
        #
        # @return [String] Output path
        def write
          File.open(@output_path, "wb") do |file|
            # Reserve space for header (will write at end)
            header = Header.new(
              checksum_algorithm: checksum_to_constant(@options[:toc_checksum]),
              checksum_name: checksum_needs_name(@options[:toc_checksum]) ? @options[:toc_checksum] : nil,
            )
            file.write("\x00" * header.header_size)

            # Build TOC with heap offsets
            toc = build_toc

            # Write compressed TOC
            compressed_toc = toc.compress
            toc_uncompressed_size = toc.uncompressed_size
            file.write(compressed_toc)

            # Calculate and write TOC checksum
            file.pos
            toc_checksum_data = compute_checksum(compressed_toc, @options[:toc_checksum])
            file.write(toc_checksum_data)
            toc_checksum_size = toc_checksum_data.bytesize

            # Update TOC checksum info
            toc.checksum_offset = 0
            toc.checksum_size = toc_checksum_size

            # Write heap data
            file.pos
            file.write(@heap_data)

            # Now write header at beginning
            header = Header.new(
              toc_compressed_size: compressed_toc.bytesize,
              toc_uncompressed_size: toc_uncompressed_size,
              checksum_algorithm: checksum_to_constant(@options[:toc_checksum]),
              checksum_name: checksum_needs_name(@options[:toc_checksum]) ? @options[:toc_checksum] : nil,
            )
            file.seek(0)
            file.write(header.to_bytes)
          end

          @output_path
        end

        private

        # Read file data and add to heap
        #
        # @param entry [Entry] Entry to populate
        # @param path [String] File path
        def read_and_add_file_data(entry, path)
          data = File.binread(path)
          entry.size = data.bytesize
          compress_and_add_entry_data(entry, data)
        end

        # Compress and add entry data to heap
        #
        # @param entry [Entry] Entry to populate
        # @param data [String] Uncompressed data
        def compress_and_add_entry_data(entry, data)
          return if data.nil? || data.empty?

          # Calculate extracted checksum
          entry.extracted_checksum = compute_checksum_hex(data, @options[:file_checksum])
          entry.extracted_checksum_style = @options[:file_checksum]

          # Compress data
          compressed = compress_data(data)
          entry.data_encoding = @options[:compression]
          entry.data_length = compressed.bytesize
          entry.data_size = data.bytesize

          # Calculate archived checksum
          entry.archived_checksum = compute_checksum_hex(compressed, @options[:file_checksum])
          entry.archived_checksum_style = @options[:file_checksum]

          # Add to heap
          entry.data_offset = @heap_data.bytesize
          @heap_data << compressed
        end

        # Compress data based on configured algorithm
        #
        # @param data [String] Uncompressed data
        # @return [String] Compressed data
        def compress_data(data)
          case @options[:compression]
          when COMPRESSION_GZIP
            compress_gzip(data)
          when COMPRESSION_BZIP2
            compress_bzip2(data)
          when COMPRESSION_LZMA
            compress_lzma(data)
          when COMPRESSION_XZ
            compress_xz(data)
          else
            data
          end
        end

        # Compress with gzip
        #
        # @param data [String] Uncompressed data
        # @return [String] Gzip compressed data
        def compress_gzip(data)
          level = @options[:compression_level] || DEFAULT_COMPRESSION_LEVEL
          zlib = Zlib::Deflate.new(level, -Zlib::MAX_WBITS)
          result = zlib.deflate(data, Zlib::FINISH)
          zlib.close
          result
        end

        # Compress with bzip2
        #
        # @param data [String] Uncompressed data
        # @return [String] Bzip2 compressed data
        def compress_bzip2(data)
          require_relative "../../algorithms/bzip2/compressor"
          compressor = Omnizip::Algorithms::Bzip2::Compressor.new(
            level: @options[:compression_level] || DEFAULT_COMPRESSION_LEVEL,
          )
          compressor.compress(data)
        end

        # Compress with LZMA
        #
        # @param data [String] Uncompressed data
        # @return [String] LZMA compressed data
        def compress_lzma(data)
          require_relative "../../algorithms/lzma/encoder"
          encoder = Omnizip::Algorithms::Lzma::Encoder.new(
            level: @options[:compression_level] || DEFAULT_COMPRESSION_LEVEL,
          )
          encoder.encode(data)
        end

        # Compress with XZ
        #
        # @param data [String] Uncompressed data
        # @return [String] XZ compressed data
        def compress_xz(data)
          require_relative "../xz"
          output = StringIO.new
          writer = Omnizip::Formats::Xz::StreamWriter.new(output,
                                                          level: @options[:compression_level] || DEFAULT_COMPRESSION_LEVEL)
          writer.write(data)
          writer.close
          output.string
        end

        # Compute checksum (returns binary data)
        #
        # @param data [String] Data to checksum
        # @param algorithm [String] Checksum algorithm
        # @return [String] Binary checksum
        def compute_checksum(data, algorithm)
          case algorithm.to_s.downcase
          when "md5"
            Digest::MD5.digest(data)
          when "sha1"
            Digest::SHA1.digest(data)
          when "sha224"
            Digest::SHA2.new(224).digest(data)
          when "sha256"
            Digest::SHA256.digest(data)
          when "sha384"
            Digest::SHA2.new(384).digest(data)
          when "sha512"
            Digest::SHA512.digest(data)
          else
            ""
          end
        end

        # Compute checksum as hex string (for XML attributes)
        #
        # @param data [String] Data to checksum
        # @param algorithm [String] Checksum algorithm
        # @return [String] Hex checksum string
        def compute_checksum_hex(data, algorithm)
          case algorithm.to_s.downcase
          when "md5"
            Digest::MD5.hexdigest(data)
          when "sha1"
            Digest::SHA1.hexdigest(data)
          when "sha224"
            Digest::SHA2.new(224).hexdigest(data)
          when "sha256"
            Digest::SHA256.hexdigest(data)
          when "sha384"
            Digest::SHA2.new(384).hexdigest(data)
          when "sha512"
            Digest::SHA512.hexdigest(data)
          else
            ""
          end
        end

        # Convert checksum name to constant
        #
        # @param name [String] Checksum name
        # @return [Integer] Checksum constant
        def checksum_to_constant(name)
          case name.to_s.downcase
          when "none"
            CKSUM_NONE
          when "sha1"
            CKSUM_SHA1
          when "md5"
            CKSUM_MD5
          else
            CKSUM_OTHER
          end
        end

        # Check if checksum needs name in header
        #
        # @param name [String] Checksum name
        # @return [Boolean] true if name needed
        def checksum_needs_name(name)
          !["none", "sha1", "md5"].include?(name.to_s.downcase)
        end

        # Build TOC from entries
        #
        # @return [Toc] TOC object
        def build_toc
          toc = Toc.new
          toc.checksum_style = @options[:toc_checksum]

          @entries.each do |entry|
            toc.add_entry(entry)
          end

          toc
        end
      end
    end
  end
end
