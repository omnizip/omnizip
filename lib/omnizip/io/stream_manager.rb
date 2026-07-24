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

require "stringio"

module Omnizip
  module IO
    # Manages I/O operations and wraps various source types.
    #
    # This class provides a unified interface for different I/O sources
    # including files, IO objects, and strings.
    class StreamManager
      attr_reader :source

      # Initialize stream manager.
      #
      # @param source [String, IO, File, StringIO] Input source
      # @param mode [String] File mode (for file paths)
      def initialize(source, mode: "rb")
        @source = normalize_source(source, mode)
        @owned = source.is_a?(String) && File.exist?(source)
      end

      # Create a buffered input from the source.
      #
      # @param buffer_size [Integer] Buffer size
      # @return [BufferedInput] Buffered input stream
      def buffered_input(buffer_size: BufferedInput::DEFAULT_BUFFER_SIZE)
        BufferedInput.new(@source, buffer_size: buffer_size)
      end

      # Create a buffered output to the source.
      #
      # @param buffer_size [Integer] Buffer size
      # @return [BufferedOutput] Buffered output stream
      def buffered_output(buffer_size: BufferedOutput::DEFAULT_BUFFER_SIZE)
        BufferedOutput.new(@source, buffer_size: buffer_size)
      end

      # Read all data from source.
      #
      # @return [String] All data from source
      def read_all
        @source.read
      end

      # Write data to source.
      #
      # @param data [String] Data to write
      # @return [Integer] Number of bytes written
      def write(data)
        @source.write(data)
      end

      # Close the underlying source if owned.
      #
      # @return [void]
      def close
        @source.close if @owned && @source.respond_to?(:close)
      end

      # Check if source is at end.
      #
      # @return [Boolean] True if at EOF
      def eof?
        @source.eof? if @source.respond_to?(:eof?)
      end

      private

      def normalize_source(source, mode)
        case source
        when String
          normalize_string_source(source, mode)
        when IO, File, StringIO
          source
        else
          validate_io_interface(source)
        end
      end

      def normalize_string_source(source, mode)
        if File.exist?(source)
          File.open(source, mode)
        else
          StringIO.new(source)
        end
      end

      def validate_io_interface(source)
        if source.respond_to?(:read) || source.respond_to?(:write)
          source
        else
          raise ArgumentError,
                "Invalid source type: #{source.class}"
        end
      end
    end
  end
end
