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

module Omnizip
  module Algorithms
    class Zstandard
      module Frame
        # Zstandard frame header parser (RFC 8878 Section 3.1.1.1)
        #
        # Frame_Header structure:
        # - Frame_Header_Descriptor: 1 byte
        # - Window_Descriptor: 0-1 byte (optional)
        # - Dictionary_ID: 0-4 bytes (optional)
        # - Frame_Content_Size: 0-8 bytes (optional)
        class Header
          include Constants

          # @return [Integer] Frame content size flag (bits 6-7)
          attr_reader :content_size_flag

          # @return [Boolean] Single segment flag (bit 5)
          attr_reader :single_segment

          # @return [Integer] Content checksum flag (bit 2)
          attr_reader :checksum_flag

          # @return [Integer] Dictionary ID flag (bits 0-1)
          attr_reader :dictionary_id_flag

          # @return [Integer, nil] Window log value
          attr_reader :window_log

          # @return [Integer, nil] Dictionary ID
          attr_reader :dictionary_id

          # @return [Integer, nil] Frame content size
          attr_reader :content_size

          # @return [Integer] Total header size in bytes
          attr_reader :header_size

          # Parse frame header from input
          #
          # @param input [IO] Input stream positioned at frame header
          # @return [Header] Parsed header
          def self.parse(input)
            parse_from(input.read, 0).first
          end

          # Parse frame header from a byte string.
          #
          # @param data [String]
          # @param pos [Integer] offset of the descriptor byte
          # @return [Array(Header, Integer)] header and position after
          #   the header
          def self.parse_from(data, pos)
            descriptor = data.getbyte(pos)

            header = new(descriptor)
            offset = pos + 1

            if header.window_descriptor?
              header.parse_window_descriptor_byte(data.getbyte(offset))
              offset += 1
            end

            if header.dictionary_id?
              size = header.dictionary_id_size
              bytes = data.byteslice(offset, size)
              offset += size
              header.assign_dictionary_id(bytes)
            end

            if header.content_size?
              size = header.content_size_size
              bytes = data.byteslice(offset, size)
              offset += size
              header.assign_content_size(bytes)
            end

            [header, offset]
          end

          # Initialize with descriptor byte
          #
          # @param descriptor [Integer] Frame header descriptor byte
          def initialize(descriptor)
            @descriptor = descriptor

            # Extract flags from descriptor byte
            @content_size_flag = (descriptor >> 6) & 0x03
            @single_segment = (descriptor >> 5).allbits?(0x01)
            @checksum_flag = (descriptor >> 2) & 0x01
            @dictionary_id_flag = descriptor & 0x03

            @window_log = nil
            @window_mantissa = 0
            @dictionary_id = nil
            @content_size = nil
            @header_size = 1
          end

          # Check if window descriptor is present
          #
          # @return [Boolean]
          def window_descriptor?
            !@single_segment
          end

          # Check if dictionary ID is present
          #
          # @return [Boolean]
          def dictionary_id?
            @dictionary_id_flag != 0
          end

          # Check if content size is present
          #
          # @return [Boolean]
          def content_size?
            @content_size_flag != 0 || @single_segment
          end

          # Check if content checksum is present
          #
          # @return [Boolean]
          def content_checksum?
            @checksum_flag == 1
          end

          # Get the size of dictionary ID field
          #
          # @return [Integer]
          def dictionary_id_size
            case @dictionary_id_flag
            when 0 then 0
            when 1 then 1
            when 2 then 2
            when 3 then 4
            end
          end

          # Get the size of content size field
          #
          # @return [Integer]
          def content_size_size
            if @single_segment
              # For single segment, FCS size depends on content_size_flag
              case @content_size_flag
              when 0 then 1
              when 1 then 2
              when 2 then 4
              when 3 then 8
              end
            else
              case @content_size_flag
              when 0 then 0
              when 1 then 2
              when 2 then 4
              when 3 then 8
              end
            end
          end

          # Get window size
          #
          # windowAdd = (windowBase / 8) * Mantissa (RFC 8878
          # §3.1.1.1.2); the mantissa occupies descriptor bits 0-2 and
          # the exponent bits 3-7.
          #
          # @return [Integer, nil] Window size or nil if not applicable
          def window_size
            return nil unless @window_log

            window_base = 1 << @window_log
            window_base + ((window_base / 8) * @window_mantissa)
          end

          # Parse window descriptor byte
          def parse_window_descriptor_byte(byte)
            @window_mantissa = byte & 0x07
            @window_log = 10 + ((byte >> 3) & 0x1F)
            @header_size += 1
          end

          # Assign the dictionary ID from its wire bytes.
          def assign_dictionary_id(bytes)
            @dictionary_id = case bytes.bytesize
                             when 1 then bytes.ord
                             when 2 then bytes.unpack1("v")
                             when 4 then bytes.unpack1("V")
                             end

            @header_size += bytes.bytesize
          end

          # Assign the content size from its wire bytes.
          def assign_content_size(bytes)
            @content_size = case bytes.bytesize
                            when 1 then bytes.ord
                            when 2 then bytes.unpack1("v") + 256
                            when 4 then bytes.unpack1("V")
                            when 8
                              low, high = bytes.unpack("VV")
                              low + (high << 32)
                            end

            @header_size += bytes.bytesize
          end
        end
      end
    end
  end
end
