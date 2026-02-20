# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "allocation_table"
require_relative "dirent"
require_relative "ranges_io"

module Omnizip
  module Formats
    module Ole
      # OLE compound document storage
      #
      # Main class for reading and writing OLE compound documents.
      # Provides access to the hierarchical file structure within the document.
      class Storage
        include Constants

        # OLE format error
        class FormatError < StandardError; end

        # @return [IO] Underlying IO object
        attr_reader :io

        # @return [Boolean] Whether to close IO on #close
        attr_reader :close_parent

        # @return [Boolean] Whether opened for writing
        attr_reader :writeable

        # @return [Header] Parsed header
        attr_reader :header

        # @return [AllocationTable::Big] Big block allocation table
        attr_reader :bbat

        # @return [AllocationTable::Small] Small block allocation table
        attr_reader :sbat

        # @return [RangesIO] Small block file
        attr_reader :sb_file

        # @return [Dirent] Root entry
        attr_reader :root

        # @return [Array<Dirent>] All dirents (flat list)
        attr_reader :dirents

        # Open OLE file
        #
        # @param path_or_io [String, IO] File path or IO object
        # @param mode [String, nil] Open mode
        # @yield [Storage]
        # @return [Storage]
        def self.open(path_or_io, mode = nil)
          storage = new(path_or_io, mode)
          if block_given?
            begin
              yield storage
            ensure
              storage.close
            end
          else
            storage
          end
        end

        # Initialize storage
        #
        # @param path_or_io [String, IO] File path or IO object
        # @param mode [String, nil] Open mode
        def initialize(path_or_io, mode = nil)
          @close_parent, @io = if path_or_io.is_a?(String)
                                 mode ||= "rb"
                                 [true, File.open(path_or_io, mode)]
                               else
                                 raise ArgumentError, "Cannot specify mode with IO object" if mode

                                 [false, path_or_io]
                               end

          # Force binary encoding
          @io.set_encoding(Encoding::ASCII_8BIT) if @io.respond_to?(:set_encoding)

          # Determine if writable
          @writeable = determine_writeable(mode)

          @sb_file = nil

          # Load or create
          if @io.size.positive?
            load
          else
            create_empty
          end
        end

        # Load OLE document from IO
        def load
          @io.rewind
          header_block = @io.read(HEADER_BLOCK_SIZE)

          # Parse header
          @header = Header.parse(header_block)

          # Build BBAT chain from header
          @bbat = AllocationTable::Big.new(self)
          bbat_chain = header_block[HEADER_SIZE..].unpack("V*")

          # Add Meta BAT blocks if present
          mbat_block = @header.mbat_start
          @header.num_mbat.times do
            blocks = @bbat.read([mbat_block]).unpack("V*")
            mbat_block = blocks.pop
            bbat_chain += blocks
          end

          # Load BBAT
          @bbat.load(@bbat.read(bbat_chain[0, @header.num_bat]))

          # Load dirents
          raw_dirents = @bbat.read(@header.dirent_start)
          @dirents = []
          (raw_dirents.bytesize / DIRENT_SIZE).times do |i|
            dirent_data = raw_dirents.byteslice(i * DIRENT_SIZE, DIRENT_SIZE)
            @dirents << Dirent.parse(self, dirent_data)
          end

          # Build tree structure
          @root = build_tree(@dirents).first

          # Remove empty entries
          @dirents.reject!(&:empty?)

          # Setup SBAT
          @sb_file = RangesIOResizeable.new(@bbat, first_block: @root.first_block, size: @root.size)
          @sbat = AllocationTable::Small.new(self)
          @sbat.load(@bbat.read(@header.sbat_start))
        end

        # Build tree from flat dirent list
        #
        # @param dirents [Array<Dirent>]
        # @param idx [Integer]
        # @return [Array<Dirent>]
        def build_tree(dirents, idx = 0)
          return [] if idx == EOT

          dirent = dirents[idx]

          # Build children recursively
          build_tree(dirents, dirent.child).each { |child| dirent << child }

          # Set index
          dirent.idx = idx

          # Return list for tree building
          build_tree(dirents, dirent.prev) + [dirent] + build_tree(dirents, dirent.next)
        end

        # Close storage
        def close
          @sb_file&.close
          @io.close if @close_parent
        end

        # Get appropriate BAT for size
        #
        # @param size [Integer] File size
        # @return [AllocationTable]
        def bat_for_size(size)
          size >= @header.threshold ? @bbat : @sbat
        end

        # List entries at path
        #
        # @param path [String] Directory path
        # @return [Array<String>]
        def list(path = "/")
          dirent = find_dirent(path)
          return [] unless dirent

          dirent.children.map(&:name)
        end

        # Read file content
        #
        # @param path [String] File path
        # @return [String]
        def read(path)
          dirent = find_dirent(path)
          raise Errno::ENOENT, path unless dirent
          raise Errno::EISDIR, path if dirent.dir?

          dirent.read
        end

        # Check if entry exists
        #
        # @param path [String]
        # @return [Boolean]
        def exist?(path)
          !find_dirent(path).nil?
        end

        alias exists? :exist?

        # Check if path is a file
        #
        # @param path [String]
        # @return [Boolean]
        def file?(path)
          dirent = find_dirent(path)
          dirent&.file?
        end

        # Check if path is a directory
        #
        # @param path [String]
        # @return [Boolean]
        def directory?(path)
          dirent = find_dirent(path)
          dirent&.dir?
        end

        # Get entry info
        #
        # @param path [String]
        # @return [Hash, nil]
        def info(path)
          dirent = find_dirent(path)
          return nil unless dirent

          {
            name: dirent.name,
            type: dirent.type,
            size: dirent.size,
            create_time: dirent.create_time,
            modify_time: dirent.modify_time,
          }
        end

        # Find dirent by path
        #
        # @param path [String]
        # @return [Dirent, nil]
        def find_dirent(path)
          path = path.to_s
          path = path[1..] if path.start_with?("/")

          return @root if path.empty?

          parts = path.split("/")
          current = @root

          parts.each do |part|
            next if part.empty?
            return nil if current.file?

            current = current / part
            return nil unless current
          end

          current
        end

        # Inspect
        def inspect
          "#<#{self.class} io=#{@io.inspect} root=#{@root.inspect}>"
        end

        private

        # Determine if IO is writable
        def determine_writeable(mode)
          return false if mode&.include?("r") && !mode.include?("+")

          if mode
            mode.include?("w") || mode.include?("a") || mode.include?("+")
          else
            begin
              @io.flush
              @io.write_nonblock("") if @io.respond_to?(:write_nonblock)
              true
            rescue IOError, Errno::EBADF
              false
            end
          end
        end

        # Create empty OLE document
        def create_empty
          @header = Header.create
          @bbat = AllocationTable::Big.new(self)
          @root = Dirent.create(self, type: :root, name: "Root Entry")
          @root.idx = 0
          @dirents = [@root]
          @sb_file = RangesIOResizeable.new(@bbat, first_block: EOC)
          @sbat = AllocationTable::Small.new(self)
          @io.truncate(0)
        end
      end
    end
  end
end
