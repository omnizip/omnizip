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
    #   buffer = StringIO.new
    #   Omnizip::Zip::OutputStream.open(buffer) do |zos|
    #     archive = MemoryArchive.new(zos, :zip)
    #     archive.add('file.txt', 'content')
    #   end
    #
    # @example Reading an archive
    #   Omnizip::Zip::InputStream.open(buffer) do |zis|
    #     archive = MemoryArchive.new(zis, :zip)
    #     archive.each_entry do |entry|
    #       puts entry.name
    #     end
    #   end
    class MemoryArchive
      attr_reader :format, :stream

      # Initialize memory archive wrapper
      #
      # @param stream [Omnizip::Zip::OutputStream, Omnizip::Zip::InputStream]
      #   Underlying stream
      # @param format [Symbol] Archive format (:zip, :seven_zip)
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

        case stream
        when Omnizip::Zip::OutputStream
          stream.put_next_entry(name, **options)
          stream.write(data) unless name.end_with?("/")
        else
          raise NotImplementedError,
                "Unsupported stream type: #{stream.class}"
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
      def add_data(name, **options, &block)
        ensure_write_mode!
        data = block.call
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
      def each_entry(&block)
        ensure_read_mode!

        case stream
        when Omnizip::Zip::InputStream
          while (zip_entry = stream.get_next_entry)
            entry = Entry.new(zip_entry, stream)
            block.call(entry)
          end
        else
          raise NotImplementedError,
                "Unsupported stream type: #{stream.class}"
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

        case stream
        when Omnizip::Zip::OutputStream
          # OutputStream wraps the IO, we need to get the underlying buffer
          # This is only safe after close
          unless stream.closed?
            raise "Archive must be closed before accessing data"
          end

          # The buffer was passed in during creation, but we don't have
          # direct access. This method should be called on the StringIO
          # returned by Buffer.create instead.
          raise NotImplementedError,
                "Use Buffer.create return value instead"
        else
          raise "Cannot get string from read mode archive"
        end
      end

      # Entry wrapper with read capability
      #
      # Wraps underlying ZIP entry to provide consistent interface
      # for reading entry data from the stream.
      class Entry
        attr_reader :name, :size, :compressed_size, :time, :comment

        # Initialize entry wrapper
        #
        # @param entry [Omnizip::Zip::Entry] Underlying entry
        # @param stream [Omnizip::Zip::InputStream] Stream to read from
        def initialize(entry, stream)
          @entry = entry
          @stream = stream
          @name = entry.name
          @size = entry.size
          @compressed_size = entry.compressed_size
          @time = entry.time
          @comment = entry.comment
          @directory = entry.directory?
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
          @stream.read(size)
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

      # Ensure stream is in write mode (OutputStream)
      #
      # @raise [RuntimeError] If not in write mode
      def ensure_write_mode!
        return if stream.is_a?(Omnizip::Zip::OutputStream)

        raise "Operation requires write mode (OutputStream)"
      end

      # Ensure stream is in read mode (InputStream)
      #
      # @raise [RuntimeError] If not in read mode
      def ensure_read_mode!
        return if stream.is_a?(Omnizip::Zip::InputStream)

        raise "Operation requires read mode (InputStream)"
      end
    end
  end
end
