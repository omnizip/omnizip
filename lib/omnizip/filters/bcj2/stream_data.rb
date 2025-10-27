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

require_relative "constants"

module Omnizip
  module Filters
    # Model class representing the 4 BCJ2 streams.
    #
    # BCJ2 splits data into:
    # - Main stream: Non-convertible bytes
    # - Call stream: CALL (E8) instruction addresses
    # - Jump stream: JUMP (E9) instruction addresses
    # - RC stream: Range coder probability data
    class Bcj2StreamData
      include Bcj2Constants

      attr_accessor :main, :call, :jump, :rc

      # Initialize empty streams.
      #
      # @return [Bcj2StreamData] New stream data instance
      def initialize
        @main = String.new(encoding: Encoding::BINARY)
        @call = String.new(encoding: Encoding::BINARY)
        @jump = String.new(encoding: Encoding::BINARY)
        @rc = String.new(encoding: Encoding::BINARY)
      end

      # Get stream by index.
      #
      # @param index [Integer] Stream index (0-3)
      # @return [String] Stream data
      # @raise [ArgumentError] If index is invalid
      def [](index)
        case index
        when STREAM_MAIN then @main
        when STREAM_CALL then @call
        when STREAM_JUMP then @jump
        when STREAM_RC then @rc
        else
          raise ArgumentError, "Invalid stream index: #{index}"
        end
      end

      # Set stream by index.
      #
      # @param index [Integer] Stream index (0-3)
      # @param data [String] Stream data
      # @return [String] The data that was set
      # @raise [ArgumentError] If index is invalid
      def []=(index, data)
        case index
        when STREAM_MAIN then @main = data
        when STREAM_CALL then @call = data
        when STREAM_JUMP then @jump = data
        when STREAM_RC then @rc = data
        else
          raise ArgumentError, "Invalid stream index: #{index}"
        end
      end

      # Get all streams as an array.
      #
      # @return [Array<String>] Array of 4 streams
      def to_a
        [@main, @call, @jump, @rc]
      end

      # Check if all streams are empty.
      #
      # @return [Boolean] True if all streams are empty
      def empty?
        @main.empty? && @call.empty? && @jump.empty? && @rc.empty?
      end
    end
  end
end
