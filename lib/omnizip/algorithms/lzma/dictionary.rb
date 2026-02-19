# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Circular buffer dictionary for LZMA sliding window
      # Ported from XZ Utils lzma_decoder.c
      class Dictionary
        attr_reader :size, :position, :buffer

        def initialize(size)
          @size = size
          @buffer = String.new(encoding: Encoding::BINARY)
          @position = 0
        end

        # Append bytes to dictionary
        def append(data)
          data.each_byte do |byte|
            @buffer << byte
            @position += 1

            # Trim if exceeds size
            if @buffer.bytesize > @size
              excess = @buffer.bytesize - @size
              @buffer = @buffer.byteslice(excess..-1)
            end
          end
        end

        # Read bytes from dictionary at a distance back
        def read_bytes(distance, length)
          raise "Invalid distance: #{distance}" if distance > @buffer.bytesize

          result = String.new(encoding: Encoding::BINARY)
          src_pos = @buffer.bytesize - distance

          length.times do |i|
            byte = @buffer[(src_pos + i) % @buffer.bytesize]
            result << byte
          end

          result
        end

        # Get byte at distance back
        def get_byte(distance)
          raise "Invalid distance: #{distance}" if distance > @buffer.bytesize

          @buffer.getbyte(@buffer.bytesize - distance)
        end

        # Reset dictionary
        def reset!
          @buffer.clear
          @position = 0
        end

        # Clone dictionary
        def clone
          dict = Dictionary.new(@size)
          dict.instance_variable_set(:@buffer, @buffer.dup)
          dict.instance_variable_set(:@position, @position)
          dict
        end
      end
    end
  end
end
