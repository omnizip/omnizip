# frozen_string_literal: true

require "set"
require_relative "constants"

module Omnizip
  module Formats
    module Ole
      # OLE allocation table
      #
      # Manages block chains for files stored in OLE containers.
      # There are two types: Big (BBAT) and Small (SBAT).
      class AllocationTable
        include Constants

        # @return [Array<Integer>] Table entries
        attr_reader :entries

        # @return [Object] Parent OLE storage
        attr_reader :ole

        # @return [IO] Underlying IO
        attr_reader :io

        # @return [Integer] Block size in bytes
        attr_reader :block_size

        # Initialize allocation table
        #
        # @param ole [Object] Parent OLE storage
        def initialize(ole)
          @ole = ole
          @entries = []
        end

        # Load allocation table from binary data
        #
        # @param data [String] Binary data containing table entries
        def load(data)
          @entries = data.unpack("V*")
        end

        # Get entry at index
        #
        # @param idx [Integer] Entry index
        # @return [Integer] Entry value
        def [](idx)
          @entries[idx]
        end

        # Set entry at index
        #
        # @param idx [Integer] Entry index
        # @param val [Integer] Entry value
        def []=(idx, val)
          @entries[idx] = val
        end

        # Get number of entries
        #
        # @return [Integer] Entry count
        def length
          @entries.length
        end

        # Follow chain from starting index
        #
        # @param idx [Integer] Starting block index
        # @return [Array<Integer>] Chain of block indices
        # @raise [ArgumentError] If chain is broken
        def chain(idx)
          result = []
          visited = Set.new

          until idx >= META_BAT
            if idx.negative? || idx > length
              raise ArgumentError, "Broken allocation chain at index #{idx}"
            end

            if visited.include?(idx)
              raise ArgumentError, "Circular chain detected at index #{idx}"
            end

            visited << idx
            result << idx
            idx = @entries[idx]
          end

          result
        end

        # Convert block chain to byte ranges
        #
        # @param blocks [Array<Integer>] Block indices
        # @param size [Integer, nil] Optional size to truncate to
        # @return [Array<Array<Integer, Integer>>] Array of [offset, length] pairs
        def blocks_to_ranges(blocks, size = nil)
          return [] if blocks.empty?

          # Truncate chain if size specified
          blocks = blocks[0, (size.to_f / block_size).ceil] if size

          # Convert to ranges
          ranges = blocks.map { |i| [block_size * i, block_size] }

          # Truncate final range if needed
          if ranges.last && size
            ranges.last[1] -= ((ranges.length * block_size) - size)
          end

          ranges
        end

        # Get ranges for a chain
        #
        # @param chain_or_idx [Array<Integer>, Integer] Block chain or head index
        # @param size [Integer, nil] Optional size
        # @return [Array<Array<Integer, Integer>>] Byte ranges
        def ranges(chain_or_idx, size = nil)
          blocks = chain_or_idx.is_a?(Array) ? chain_or_idx : chain(chain_or_idx)
          blocks_to_ranges(blocks, size)
        end

        # Read data from block chain
        #
        # @param chain_or_idx [Array<Integer>, Integer] Block chain or head index
        # @param size [Integer, nil] Optional size
        # @return [String] Data from chain
        def read(chain_or_idx, size = nil)
          ranges = self.ranges(chain_or_idx, size)
          data = "".b

          ranges.each do |offset, len|
            @io.seek(offset)
            data << @io.read(len).to_s
          end

          data
        end

        # Find a free block
        #
        # @return [Integer] Free block index
        def free_block
          idx = @entries.index(AVAIL)
          return idx if idx

          @entries << AVAIL
          @entries.length - 1
        end

        # Resize a block chain
        #
        # @param blocks [Array<Integer>] Current blocks (modified in place)
        # @param size [Integer] New size in bytes
        # @return [Array<Integer>] Updated blocks
        def resize_chain(blocks, size)
          new_num_blocks = (size / block_size.to_f).ceil
          old_num_blocks = blocks.length

          if new_num_blocks < old_num_blocks
            # De-allocate excess blocks
            (new_num_blocks...old_num_blocks).each do |i|
              @entries[blocks[i]] = AVAIL
            end
            if new_num_blocks.positive?
              @entries[blocks[new_num_blocks - 1]] =
                EOC
            end
            blocks.slice!(new_num_blocks..-1)
          elsif new_num_blocks > old_num_blocks
            # Allocate more blocks
            last_block = blocks.last
            (new_num_blocks - old_num_blocks).times do
              block = free_block
              @entries[last_block] = block if last_block
              blocks << block
              last_block = block
              @entries[last_block] = EOC
            end
          end

          blocks
        end

        # Truncate table to remove trailing AVAIL entries
        #
        # @return [Array<Integer>] Truncated entries
        def truncate
          temp = @entries.reverse
          first_non_avail = temp.find { |b| b != AVAIL }
          temp = temp[temp.index(first_non_avail)..] if first_non_avail
          temp.reverse
        end

        # Truncate entries in place
        def truncate_entries
          @entries.replace(truncate)
        end

        # Pack table to binary data
        #
        # @return [String] Binary data
        def pack
          table = truncate

          # Pad to block boundary
          num = @ole.bbat.block_size / 4
          if (table.length % num) != 0
            table += [AVAIL] * (num - (table.length % num))
          end

          table.pack("V*")
        end

        # Big allocation table (BBAT)
        #
        # Manages large blocks (typically 512 bytes) for files >= 4096 bytes.
        class Big < AllocationTable
          def initialize(ole)
            super
            @block_size = 1 << @ole.header.b_shift
            @io = @ole.io
          end

          # Big blocks are -1 based to avoid clashing with header
          #
          # @param blocks [Array<Integer>] Block indices
          # @param size [Integer, nil] Optional size
          # @return [Array<Array<Integer, Integer>>] Byte ranges
          def blocks_to_ranges(blocks, size = nil)
            return [] if blocks.empty?

            blocks = blocks[0, (size.to_f / block_size).ceil] if size
            ranges = blocks.map { |i| [block_size * (i + 1), block_size] }
            ranges.last[1] -= ((ranges.length * block_size) - size) if ranges.last && size
            ranges
          end
        end

        # Small allocation table (SBAT)
        #
        # Manages small blocks (typically 64 bytes) for files < 4096 bytes.
        class Small < AllocationTable
          def initialize(ole)
            super
            @block_size = 1 << @ole.header.s_shift
            @io = @ole.sb_file
          end
        end
      end
    end
  end
end
