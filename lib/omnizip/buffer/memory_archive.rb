# frozen_string_literal: true

module Omnizip
  module Buffer
    # Wrapper for in-memory archive operations
    #
    # Provides unified interface for adding entries to and reading entries
    # from archives stored in memory (StringIO). Works with both OutputStream
    # (for creating) and InputStream (for reading).
    #
    # @example Creating an archive
    #   writer = Formats::Zip::Writer.new(nil)
    #   archive = MemoryArchive.new(writer, :zip)
    #   archive.add('file.txt', 'content')
    #   writer.write_to_io(buffer)
    #
    # @example Reading an archive
    #   archive = MemoryArchive.new(Formats::Zip::Reader.new(path), :zip)
    #   archive.each_entry do |entry|
    #     puts entry.name
    #   end
    class MemoryArchive
      attr_reader :format, :stream

      # Initialize memory archive wrapper
      #
      # @param stream [Formats::Zip::Writer, Formats::Zip::Reader]
      #   Native writer (write mode) or reader (read mode)
      # @param format [Symbol] Archive format (:zip)
      def initialize(stream, format)
        @stream = stream
        @format = format
        @entries_cache = nil
      end

      # Add file from memory (write mode only)
      #
      # @param name [String] Entry name (path within archive)
      # @param data [String] Entry content
      # @param options [Hash] Entry options
      # @option options [Time] :time Modification time (default: now)
      # @option options [String] :comment Entry comment
      # @option options [Symbol] :compression Compression method
      #   (:store, :deflate)
      # @option options [Integer] :level Compression level (1-9)
      # @return [self] For method chaining
      #
      # @example Add multiple files
      #   archive.add('file1.txt', 'content1')
      #          .add('file2.txt', 'content2')
      #          .add('dir/', '')  # Directory entry
      #
      # @raise [RuntimeError] If stream is not an OutputStream
      def add(name, data, **options)
        ensure_write_mode!

        if name.end_with?("/") && data.to_s.empty?
          stream.add_directory(name)
        else
          method = if options[:compression] == :store
                     Formats::Zip::Constants::COMPRESSION_STORE
                   end
          stream.add_data(name, data, nil, compression_method: method)
        end

        self
      end

      # Add data with block (write mode only)
      #
      # @param name [String] Entry name
      # @param options [Hash] Entry options
      # @yield Block that returns content
      # @yieldreturn [String] Entry content
      # @return [self] For method chaining
      #
      # @example Add with block
      #   archive.add_data('file.txt') { File.read('source.txt') }
      def add_data(name, **options)
        ensure_write_mode!
        data = yield
        add(name, data, **options)
      end

      # Iterate entries (read mode only)
      #
      # @yield [entry] Block called for each entry
      # @yieldparam entry [Entry] Archive entry
      # @return [void]
      #
      # @example Process all entries
      #   archive.each_entry do |entry|
      #     puts "#{entry.name}: #{entry.size} bytes"
      #     content = entry.read unless entry.directory?
      #   end
      #
      # @raise [RuntimeError] If stream is not an InputStream
      def each_entry
        ensure_read_mode!

        stream.entries.each do |zip_entry|
          yield(Entry.new(zip_entry, stream))
        end
      end

      # Extract all entries to memory (read mode only)
      #
      # @return [Hash<String, String>] Filename => content mapping
      #
      # @example Extract all
      #   files = archive.extract_all_to_memory
      #   files.each { |name, content| puts "#{name}: #{content.size}" }
      def extract_all_to_memory
        ensure_read_mode!

        result = {}
        each_entry do |entry|
          result[entry.name] = entry.read unless entry.directory?
        end
        result
      end

      # Get underlying buffer as string (write mode only)
      #
      # @return [String] Complete archive as binary string
      #
      # @example Get archive data
      #   archive_data = archive.to_s
      #   File.binwrite('output.zip', archive_data)
      #
      # @raise [RuntimeError] If stream is not an OutputStream
      def to_s
        ensure_write_mode!

        # The buffer is owned by Buffer.create; this method should be
        # called on the StringIO it returns instead.
        raise NotImplementedError,
              "Use Buffer.create return value instead"
      end

      # Entry wrapper with read capability
      #
      # Wraps underlying ZIP entry to provide consistent interface
      # for reading entry data from the stream.
      class Entry
        attr_reader :name, :size, :compressed_size, :time, :comment

        # Initialize entry wrapper
        #
        # @param entry [Formats::Zip::CentralDirectoryHeader] entry
        # @param reader [Formats::Zip::Reader] Native archive reader
        def initialize(entry, reader)
          @entry = entry
          @reader = reader
          @name = entry.filename
          @size = entry.uncompressed_size
          @compressed_size = entry.compressed_size
          @time = entry.time
          @comment = entry.comment.to_s
          @directory = entry.directory?
          @content = nil
          @pos = 0
        end

        # Read entry content
        #
        # @param size [Integer, nil] Number of bytes to read (nil for all)
        # @return [String, nil] Entry data or nil if EOF
        #
        # @example Read entire entry
        #   content = entry.read
        #
        # @example Read in chunks
        #   while (chunk = entry.read(8192))
        #     process_chunk(chunk)
        #   end
        def read(size = nil)
          # IO-like streaming semantics: successive reads return
          # successive chunks, nil at end-of-content. Callers like
          # Pipe::StreamDecompressor loop on this — a read that
          # always returns data would loop forever.
          @content ||= @reader.read_entry(@name)
          return nil if @pos >= @content.bytesize

          chunk = if size
                    @content.byteslice(@pos, size)
                  else
                    @content.byteslice(@pos, @content.bytesize - @pos)
                  end
          @pos += chunk.bytesize
          chunk
        end

        # Check if entry is a directory
        #
        # @return [Boolean] True if directory entry
        def directory?
          @directory
        end

        # Check if entry is a file
        #
        # @return [Boolean] True if file entry
        def file?
          !@directory
        end

        # Get compression method
        #
        # @return [Symbol] Compression method (:store, :deflate, etc.)
        def compression_method
          @entry.compression_method
        end

        # Get CRC32 checksum
        #
        # @return [Integer] CRC32 value
        def crc32
          @entry.crc32
        end
      end

      private

      # Ensure stream is in write mode (native Writer)
      #
      # @raise [Omnizip::IOError] If not in write mode
      def ensure_write_mode!
        return if stream.is_a?(Omnizip::Formats::Zip::Writer)

        raise Omnizip::IOError,
              "Operation requires write mode (Formats::Zip::Writer)"
      end

      # Ensure stream is in read mode (native Reader)
      #
      # @raise [Omnizip::IOError] If not in read mode
      def ensure_read_mode!
        return if stream.is_a?(Omnizip::Formats::Zip::Reader)

        raise Omnizip::IOError,
              "Operation requires read mode (Formats::Zip::Reader)"
      end
    end
  end
end
