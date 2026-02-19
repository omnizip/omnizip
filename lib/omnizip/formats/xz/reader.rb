# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require "stringio"
require_relative "../xz_impl/stream_decoder"

module Omnizip
  module Formats
    class Xz
      # XZ format reader
      #
      # Reads and decompresses .xz files compatible with XZ Utils.
      # Provides both low-level stream API and high-level convenience methods.
      class Reader
        # Initialize reader
        #
        # @param input [String, IO] File path or IO object
        def initialize(input)
          @input = if input.is_a?(String)
                     File.open(input, "rb")
                   elsif input.respond_to?(:read)
                     input
                   else
                     raise ArgumentError,
                           "Input must be a file path or IO object"
                   end
          @close_on_finish = input.is_a?(String)
        end

        # Read and decompress XZ data
        #
        # @return [String] Decompressed data
        def read
          XzFormat::StreamDecoder.decode(@input)
        ensure
          close if @close_on_finish
        end

        # Close the input stream if we opened it
        def close
          @input.close if @input.respond_to?(:close) && !@input.closed?
        end

        # Check if reader is open
        #
        # @return [Boolean] True if input is open
        def closed?
          @input.respond_to?(:closed?) ? @input.closed? : false
        end

        # Read in a streaming fashion (for large files)
        #
        # @yield [String] Chunks of decompressed data
        # @return [String] Full decompressed data
        def each_chunk(chunk_size = 64 * 1024)
          # For now, just read everything and yield chunks
          # TODO: Implement true streaming for memory efficiency
          data = read
          offset = 0
          while offset < data.bytesize
            chunk = data.byteslice(offset, chunk_size)
            yield chunk
            offset += chunk.bytesize
          end
          data
        end
      end

      # Entry class for extract API compatibility
      # XZ format is a single stream, so this is a simple wrapper
      class Entry
        attr_reader :data

        def initialize(data)
          @data = data
        end

        # Read the decompressed data
        #
        # @return [String] Decompressed data
        def read
          @data
        end

        # Get data size
        #
        # @return [Integer] Size in bytes
        def size
          @data.bytesize
        end

        # Alias for compatibility
        alias_method :bytesize, :size
      end
    end
  end
end
