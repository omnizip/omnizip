# frozen_string_literal: true

require "set"
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
        # @param visited [Set] Set of visited indices to detect cycles
        # @return [Array<Dirent>]
        def build_tree(dirents, idx = 0, visited = nil)
          return [] if idx == EOT

          # Initialize visited set on first call
          visited ||= Set.new

          # Check for circular references
          return [] if visited.include?(idx)

          visited << idx

          dirent = dirents[idx]
          return [] unless dirent

          # Build children recursively
          build_tree(dirents, dirent.child, visited).each { |child| dirent << child }

          # Set index
          dirent.idx = idx

          # Return list for tree building
          build_tree(dirents, dirent.prev, visited) + [dirent] + build_tree(dirents, dirent.next, visited)
        end

        # Close storage
        def close
          @sb_file&.close
          flush if @writeable
          @io.close if @close_parent
        end

        # Flush all changes to disk
        #
        # Writes all metadata (dirents, allocation tables, header) to the file.
        # This is the main "save" method for OLE documents.
        def flush
          return unless @writeable

          # Update root dirent
          @root.name = "Root Entry"
          @root.first_block = @sb_file.first_block
          @root.size = @sb_file.size

          # Flatten dirent tree
          @dirents = @root.flatten

          # Serialize dirents using bbat
          dirent_io = RangesIOResizeable.new(@bbat, first_block: @header.dirent_start)
          dirent_io.write(@dirents.map(&:pack).join)
          # Pad to block boundary
          padding = ((dirent_io.size / @bbat.block_size.to_f).ceil * @bbat.block_size) - dirent_io.size
          dirent_io.write("\x00".b * padding) if padding.positive?
          @header.dirent_start = dirent_io.first_block
          dirent_io.close

          # Serialize sbat
          sbat_io = RangesIOResizeable.new(@bbat, first_block: @header.sbat_start)
          sbat_io.write(@sbat.pack)
          @header.sbat_start = sbat_io.first_block
          @header.num_sbat = @bbat.chain(@header.sbat_start).length
          sbat_io.close

          # Clear BAT/META_BAT markers
          @bbat.entries.each_with_index do |val, idx|
            if [BAT, META_BAT].include?(val)
              @bbat.entries[idx] = AVAIL
            end
          end

          # Calculate and allocate BAT blocks
          write_bat_blocks

          # Write header
          @io.seek(0)
          @io.write(@header.pack)
          @io.write(@bbat_chain.pack("V*"))
          @io.flush
        end

        private

        # Write BAT (Block Allocation Table) blocks
        def write_bat_blocks
          # Truncate bbat to remove trailing AVAILs
          @bbat.entries.replace(@bbat.entries.reject { |e| e == AVAIL }.push(AVAIL))

          # Calculate space needed for BAT
          num_mbat_blocks = 0
          io = RangesIOResizeable.new(@bbat, first_block: EOC)

          @bbat.truncate_entries
          @io.truncate(@bbat.block_size * (@bbat.length + 1))

          # Iteratively calculate BAT/MBAT space
          loop do
            bbat_data_len = ((@bbat.length + num_mbat_blocks) * 4 / @bbat.block_size.to_f).ceil * @bbat.block_size
            new_num_mbat_blocks = calculate_mbat_blocks(bbat_data_len)

            if new_num_mbat_blocks != num_mbat_blocks
              num_mbat_blocks = new_num_mbat_blocks
            elsif io.size != bbat_data_len
              io.truncate(bbat_data_len)
            else
              break
            end
          end

          # Get BAT chain and mark blocks
          @bbat_chain = @bbat.chain(io.first_block)
          io.close

          @bbat_chain.each { |b| @bbat.entries[b] = BAT }
          @header.num_bat = @bbat_chain.length

          # Allocate MBAT blocks if needed
          mbat_blocks = allocate_mbat_blocks(num_mbat_blocks)
          @header.mbat_start = mbat_blocks.first || EOC
          @header.num_mbat = num_mbat_blocks

          # Write BAT data
          RangesIO.open(@io, @bbat.ranges(@bbat_chain)) do |f|
            f.write(@bbat.pack)
          end

          # Write MBAT if present
          write_mbat_blocks(mbat_blocks, num_mbat_blocks) if num_mbat_blocks.positive?

          # Pad BAT chain to 109 entries in header
          @bbat_chain += [AVAIL] * [109 - @bbat_chain.length, 0].max
        end

        # Calculate number of MBAT blocks needed
        def calculate_mbat_blocks(bbat_data_len)
          excess_bat_blocks = (bbat_data_len / @bbat.block_size) - 109
          return 0 if excess_bat_blocks <= 0

          (excess_bat_blocks * 4 / (@bbat.block_size - 4).to_f).ceil
        end

        # Allocate MBAT blocks
        def allocate_mbat_blocks(count)
          (0...count).map do
            block = @bbat.free_block
            @bbat.entries[block] = META_BAT
            block
          end
        end

        # Write MBAT blocks
        def write_mbat_blocks(mbat_blocks, _num_mbat)
          # Get BAT entries beyond the first 109
          mbat_data = @bbat_chain[109..] || []

          # Add linked list pointers
          entries_per_block = (@bbat.block_size / 4) - 1
          mbat_data = mbat_data.each_slice(entries_per_block).to_a

          mbat_data.zip(mbat_blocks[1..] + [nil]).each_with_index do |(entries, next_block), idx|
            block_data = entries + (next_block ? [next_block] : [])
            # Pad to block size
            block_data += [AVAIL] * ((@bbat.block_size / 4) - block_data.length)

            RangesIO.open(@io, @bbat.ranges([mbat_blocks[idx]])) do |f|
              f.write(block_data.pack("V*"))
            end
          end
        end

        public

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
