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
    # Buffered output stream for efficient writing.
    #
    # This class provides buffered writing capabilities to minimize
    # I/O operations and improve performance.
    class BufferedOutput
      DEFAULT_BUFFER_SIZE = 65_536

      attr_reader :destination, :buffer_size, :position

      # Initialize buffered output.
      #
      # @param destination [IO, #write] Output destination
      # @param buffer_size [Integer] Size of internal buffer
      def initialize(destination, buffer_size: DEFAULT_BUFFER_SIZE)
        @destination = destination
        @buffer_size = buffer_size
        @buffer = String.new(capacity: buffer_size)
        @position = 0
      end

      # Write data to the stream.
      #
      # @param data [String] Data to write
      # @return [Integer] Number of bytes written
      def write(data)
        return 0 if data.nil? || data.empty?

        bytes_written = 0
        offset = 0

        while offset < data.bytesize
          offset = write_chunk(data, offset)
          bytes_written = offset
        end

        bytes_written
      end

      # Write a single byte.
      #
      # @param byte [Integer] Byte value (0-255)
      # @return [Integer] Number of bytes written (1)
      def write_byte(byte)
        @buffer << byte.chr
        @position += 1

        flush if @buffer.bytesize >= @buffer_size

        1
      end

      # Flush buffered data to destination.
      #
      # @return [void]
      def flush
        return if @buffer.empty?

        @destination.write(@buffer)
        @buffer.clear
      end

      # Close the stream and flush remaining data.
      #
      # @return [void]
      def close
        flush
        @destination.close if @destination.respond_to?(:close)
      end

      private

      def write_chunk(data, offset)
        available = @buffer_size - @buffer.bytesize
        to_write = [data.bytesize - offset, available].min

        @buffer << data[offset, to_write]
        @position += to_write

        flush if @buffer.bytesize >= @buffer_size

        offset + to_write
      end
    end
  end
end
