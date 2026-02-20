# frozen_string_literal: true

module Omnizip
  module Formats
    module Ole
      # Virtual IO for non-contiguous byte ranges
      #
      # Provides a contiguous IO interface over scattered byte ranges
      # in an underlying IO object.
      class RangesIO
        # @return [IO] Underlying IO object
        attr_reader :io

        # @return [Array<Array<Integer, Integer>>] Byte ranges [[offset, length], ...]
        attr_reader :ranges

        # @return [Integer] Total size in bytes
        attr_reader :size

        # @return [Integer] Current position
        attr_reader :pos

        # Initialize RangesIO
        #
        # @param io [IO] Underlying IO object
        # @param ranges [Array<Array<Integer, Integer>>] Byte ranges
        def initialize(io, ranges = [])
          @io = io
          @pos = 0
          @active = 0
          self.ranges = ranges
        end

        # Open with block support
        #
        # @yield [RangesIO]
        def self.open(io, ranges = [])
          ranges_io = new(io, ranges)
          if block_given?
            begin
              yield ranges_io
            ensure
              ranges_io.close
            end
          else
            ranges_io
          end
        end

        # Set ranges
        #
        # @param ranges [Array<Range, Array>] Byte ranges
        def ranges=(ranges)
          ranges ||= []

          # Convert Range objects to arrays, filtering out nils
          @ranges = ranges.filter_map do |r|
            next nil if r.nil?

            r.is_a?(Range) ? [r.begin, r.end - r.begin] : r
          end

          # Calculate cumulative offsets
          @size = 0
          @offsets = []
          @ranges.map(&:last).each do |len|
            @offsets << @size
            @size += len
          end

          # Reset position
          @active = 0
          @pos = 0
        end

        # Set position
        #
        # @param new_pos [Integer]
        # @param whence [Integer] IO::SEEK_SET, IO::SEEK_CUR, or IO::SEEK_END
        def pos=(new_pos, whence = ::IO::SEEK_SET)
          case whence
          when ::IO::SEEK_SET
            # use new_pos as is
          when ::IO::SEEK_CUR
            new_pos = @pos + new_pos
          when ::IO::SEEK_END
            new_pos = @size + new_pos
          else
            raise Errno::EINVAL
          end

          raise Errno::EINVAL unless (0..@size).cover?(new_pos)

          @pos = new_pos

          # Binary search for active range
          low = 0
          high = @offsets.length
          while low < high
            mid = (low + high) / 2
            if @pos < @offsets[mid]
              high = mid
            else
              low = mid + 1
            end
          end

          @active = low - 1
        end

        alias seek :pos=
        alias tell :pos

        # Rewind to beginning
        def rewind
          seek(0)
        end

        # Check if at end
        #
        # @return [Boolean]
        def eof?
          @pos == @size
        end

        # Read data
        #
        # @param limit [Integer, nil] Maximum bytes to read
        # @return [String]
        def read(limit = nil)
          data = "".b
          return data if eof?

          limit ||= @size
          return data if limit <= 0

          range_pos, range_len = @ranges[@active]
          diff = @pos - @offsets[@active]
          range_pos += diff
          range_len -= diff

          loop do
            @io.seek(range_pos)

            if limit < range_len
              chunk = @io.read(limit).to_s
              @pos += chunk.length
              data << chunk
              break
            end

            chunk = @io.read(range_len).to_s
            @pos += chunk.length
            data << chunk

            break if chunk.length != range_len

            limit -= range_len
            break if @active >= @ranges.length - 1

            @active += 1
            range_pos, range_len = @ranges[@active]
          end

          data
        end

        # Write data
        #
        # @param data [String] Data to write
        # @return [Integer] Bytes written
        def write(data)
          data = data.dup.force_encoding(Encoding::ASCII_8BIT) if data.respond_to?(:encoding)
          return 0 if data.empty?

          # Grow if needed
          if data.length > @size - @pos
            truncate(@pos + data.length)
          end

          range_pos, range_len = @ranges[@active]
          diff = @pos - @offsets[@active]
          range_pos += diff
          range_len -= diff

          written = 0

          loop do
            @io.seek(range_pos)

            if written + range_len > data.length
              chunk = data[written..]
              @io.write(chunk)
              @pos += chunk.length
              break
            end

            @io.write(data[written, range_len])
            @pos += range_len
            written += range_len

            break if @active >= @ranges.length - 1

            @active += 1
            range_pos, range_len = @ranges[@active]
          end

          data.length
        end

        alias << :write

        # Truncate (not supported by default)
        #
        # @param _size [Integer] New size
        def truncate(_size)
          raise NotImplementedError, "truncate not supported"
        end

        # Close (no-op by default)
        def close
          # No-op
        end

        # Inspect
        def inspect
          "#<#{self.class} io=#{@io.inspect}, size=#{@size}, pos=#{@pos}>"
        end
      end

      # Resizeable RangesIO backed by AllocationTable
      class RangesIOResizeable < RangesIO
        # @return [AllocationTable] Backing allocation table
        attr_reader :bat

        # @return [Integer] First block index
        attr_accessor :first_block

        # Initialize resizeable RangesIO
        #
        # @param bat [AllocationTable] Allocation table
        # @param first_block [Integer] First block index
        # @param size [Integer, nil] Optional size
        def initialize(bat, first_block:, size: nil)
          @bat = bat
          @first_block = first_block
          @blocks = first_block == Constants::EOC ? [] : bat.chain(first_block)

          super(bat.io, bat.ranges(@blocks, size))
        end

        # Truncate to new size
        #
        # @param new_size [Integer] New size in bytes
        def truncate(new_size)
          @bat.resize_chain(@blocks, new_size)
          @pos = new_size if @pos > new_size
          self.ranges = @bat.ranges(@blocks, new_size)
          @first_block = @blocks.empty? ? Constants::EOC : @blocks.first

          # Grow underlying IO if needed
          max_pos = @ranges.map { |pos, len| pos + len }.max || 0
          @io.truncate(max_pos) if max_pos > @io.size
        end
      end

      # RangesIO that can migrate between BAT and SBAT based on size
      class RangesIOMigrateable < RangesIOResizeable
        # @return [Dirent] Associated dirent
        attr_reader :dirent

        # Initialize migrateable RangesIO
        #
        # @param dirent [Dirent] Associated dirent
        # @param mode [String] Open mode
        def initialize(dirent, mode = "r")
          @dirent = dirent
          bat = dirent.ole.bat_for_size(dirent.size)
          super(bat, first_block: dirent.first_block, size: dirent.size)
          @mode = mode
        end

        # Check if writable
        def writeable?
          @mode.include?("w") || @mode.include?("a") || @mode.include?("+")
        end

        # Truncate with BAT migration support
        #
        # @param new_size [Integer] New size in bytes
        def truncate(new_size)
          new_bat = @dirent.ole.bat_for_size(new_size)

          if new_bat.instance_of?(@bat.class)
            super
          else
            # BAT migration needed
            pos = [@pos, new_size].min
            self.pos = 0
            keep = read([@size, new_size].min)
            super(0)

            @bat = new_bat
            @io = new_bat.io
            super

            self.pos = 0
            write(keep)
            self.pos = pos
          end

          # Update dirent's first_block and size after any resize
          @dirent.first_block = @first_block
          @dirent.size = new_size
        end

        # Forward first_block to dirent (for reading)
        def first_block
          @first_block
        end

        def first_block=(val)
          @first_block = val
          @dirent.first_block = val
        end
      end
    end
  end
end
