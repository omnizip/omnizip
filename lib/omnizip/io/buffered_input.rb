# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

module Omnizip
  module IO
    # Buffered input stream for efficient reading.
    #
    # This class provides buffered reading capabilities with methods
    # for reading bytes, integers, and other data types efficiently.
    class BufferedInput
      DEFAULT_BUFFER_SIZE = 65_536

      attr_reader :source, :buffer_size, :position

      # Initialize buffered input.
      #
      # @param source [IO, #read] Input source
      # @param buffer_size [Integer] Size of internal buffer
      def initialize(source, buffer_size: DEFAULT_BUFFER_SIZE)
        @source = source
        @buffer_size = buffer_size
        @buffer = String.new(capacity: buffer_size)
        @buffer_pos = 0
        @buffer_end = 0
        @position = 0
        @eof = false
      end

      # Read bytes from the stream.
      #
      # @param num_bytes [Integer] Number of bytes to read
      # @return [String, nil] Read bytes or nil if EOF
      def read(num_bytes)
        return nil if @eof && @buffer_pos >= @buffer_end

        result = String.new(capacity: num_bytes)
        read_into_result(result, num_bytes)
        result.empty? ? nil : result
      end

      # Read a single byte.
      #
      # @return [Integer, nil] Byte value (0-255) or nil if EOF
      def read_byte
        return nil if @eof && @buffer_pos >= @buffer_end

        ensure_buffer_filled
        return nil if @buffer_pos >= @buffer_end

        consume_byte
      end

      # Check if at end of stream.
      #
      # @return [Boolean] True if at EOF
      def eof?
        @eof && @buffer_pos >= @buffer_end
      end

      # Close the underlying source.
      #
      # @return [void]
      def close
        @source.close if @source.respond_to?(:close)
      end

      private

      def read_into_result(result, num_bytes)
        while result.bytesize < num_bytes && !eof?
          copy_from_buffer(result, num_bytes)
        end
      end

      def copy_from_buffer(result, num_bytes)
        available = @buffer_end - @buffer_pos
        if available.positive?
          copy_available_bytes(result, num_bytes, available)
        else
          fill_buffer
        end
      end

      def copy_available_bytes(result, num_bytes, available)
        to_copy = [num_bytes - result.bytesize, available].min
        result << @buffer[@buffer_pos, to_copy]
        @buffer_pos += to_copy
        @position += to_copy
      end

      def ensure_buffer_filled
        fill_buffer if @buffer_pos >= @buffer_end
      end

      def consume_byte
        byte = @buffer.getbyte(@buffer_pos)
        @buffer_pos += 1
        @position += 1
        byte
      end

      def fill_buffer
        return if @eof

        data = @source.read(@buffer_size)
        update_buffer(data)
      end

      def update_buffer(data)
        if data.nil? || data.empty?
          mark_eof
        else
          update_buffer_data(data)
        end
      end

      def mark_eof
        @eof = true
        @buffer = +""
        @buffer_pos = 0
        @buffer_end = 0
      end

      def update_buffer_data(data)
        @buffer = data
        @buffer_pos = 0
        @buffer_end = data.bytesize
      end
    end
  end
end
