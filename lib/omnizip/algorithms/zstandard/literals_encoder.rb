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

require_relative "constants"
require_relative "huffman_encoder"

module Omnizip
  module Algorithms
    class Zstandard
      # Literals Section Encoder (RFC 8878 Section 3.1.1.3.1)
      #
      # Encodes literals sections for Zstandard compressed blocks.
      # Supports raw, RLE, and Huffman-compressed literals.
      class LiteralsEncoder
        include Constants

        # @return [HuffmanEncoder, nil] Huffman encoder for this block
        attr_reader :huffman_encoder

        # Encode literals section
        #
        # @param literals [String] Literal bytes to encode
        # @param previous_huffman [HuffmanEncoder, nil] Previous Huffman encoder (for treeless)
        # @param use_compression [Boolean] Whether to use Huffman compression
        # @return [String] Encoded literals section
        def self.encode(literals, previous_huffman: nil, use_compression: true)
          encoder = new(literals, previous_huffman, use_compression)
          encoder.encode_section
        end

        # Initialize literals encoder
        #
        # @param literals [String] Literal bytes
        # @param previous_huffman [HuffmanEncoder, nil] Previous Huffman encoder
        # @param use_compression [Boolean] Whether to use compression
        def initialize(literals, previous_huffman = nil, use_compression = true)
          @literals = literals.to_s.dup.force_encoding(Encoding::BINARY)
          @previous_huffman = previous_huffman
          @use_compression = use_compression
          @huffman_encoder = nil
        end

        # Encode the literals section
        #
        # @return [String] Encoded section
        def encode_section
          return encode_empty if @literals.empty?

          # Choose encoding method based on data characteristics
          if rle_efficient?
            encode_rle
          elsif @use_compression && huffman_efficient?
            encode_huffman
          else
            encode_raw
          end
        end

        private

        # Check if RLE encoding would be efficient
        def rle_efficient?
          return false if @literals.length < 3

          # Check if all bytes are the same
          first_byte = @literals.getbyte(0)
          @literals.bytes.all?(first_byte)
        end

        # Check if Huffman encoding would be efficient
        def huffman_efficient?
          return false if @literals.length < 16

          # Check if data has enough redundancy
          entropy = calculate_entropy(@literals)
          entropy < 7.5 # Less than 7.5 bits per byte suggests compressibility
        end

        # Calculate Shannon entropy of data
        def calculate_entropy(data)
          return 0 if data.empty?

          # Count byte frequencies
          freq = Array.new(256, 0)
          data.each_byte { |b| freq[b] += 1 }

          # Calculate entropy
          total = data.length.to_f
          entropy = 0.0

          freq.each do |count|
            next if count.zero?

            prob = count / total
            entropy -= prob * Math.log2(prob)
          end

          entropy
        end

        # Encode empty literals
        def encode_empty
          # Type 0 (raw), size 0
          "\x00"
        end

        # Encode raw (uncompressed) literals
        def encode_raw
          size = @literals.bytesize
          header = encode_literals_header(LITERALS_BLOCK_RAW, size)
          header + @literals
        end

        # Encode RLE (run-length encoded) literals
        def encode_rle
          size = @literals.bytesize
          byte = @literals.getbyte(0)

          header = encode_literals_header(LITERALS_BLOCK_RLE, size)
          header + [byte].pack("C")
        end

        # Encode Huffman-compressed literals
        def encode_huffman
          size = @literals.bytesize

          # Build Huffman tree from literals
          @huffman_encoder = build_huffman_encoder(@literals)

          if @huffman_encoder.nil?
            # Fallback to raw if Huffman fails
            return encode_raw
          end

          # Encode literals with Huffman
          compressed = @huffman_encoder.encode(@literals)

          # Check if compression is beneficial
          # Need to account for header + table description overhead
          table_desc = @huffman_encoder.encode_table_description
          total_compressed_size = compressed.bytesize + table_desc.bytesize

          if total_compressed_size >= size
            # Not beneficial, use raw
            @huffman_encoder = nil
            return encode_raw
          end

          # Build header for LITERALS_BLOCK_COMPRESSED
          # Type (2 bits) = 10, followed by regenerated size
          header = encode_literals_header(LITERALS_BLOCK_COMPRESSED, size, total_compressed_size)

          # Build complete section: header + table_desc + compressed
          header + table_desc + compressed
        end

        # Encode literals header according to RFC 8878 Section 3.1.1.3.1
        #
        # For compressed blocks:
        # - Type (2 bits) in first byte
        # - Regenerated size (variable length)
        # - Compressed size (variable length, only for compressed type)
        def encode_literals_header(type, regenerated_size, compressed_size = nil)
          # Encode regenerated size
          if regenerated_size < 32
            # 5-bit size: type(2) + size(5) + padding(1) = 8 bits
            header_byte = (type << 6) | regenerated_size
            header = [header_byte].pack("C")
          elsif regenerated_size < 4096
            # 12-bit size
            header_byte = (type << 6) | 31
            size_field = regenerated_size - 31
            header = [header_byte, size_field & 0xFF, (size_field >> 8) & 0xFF].pack("Cv")
          else
            # 20-bit size
            header_byte = (type << 6) | 31
            # Extended size format
            header = [header_byte].pack("C")
            header += encode_extended_size(regenerated_size - 31)
          end

          # Add compressed size for LITERALS_BLOCK_COMPRESSED
          if type == LITERALS_BLOCK_COMPRESSED && compressed_size
            header + encode_compressed_size(compressed_size)
          else
            header
          end
        end

        # Encode extended size (20-bit or more)
        def encode_extended_size(size)
          if size < 128
            # Single byte
            [size].pack("C")
          elsif size < 16384
            # Two bytes
            [size | 0x80, (size >> 7) & 0x7F].pack("CC")
          else
            # Three bytes
            [size | 0x80, (size >> 7) | 0x80, (size >> 14) & 0x7F].pack("CCC")
          end
        end

        # Encode compressed size
        def encode_compressed_size(size)
          if size < 128
            [size].pack("C")
          elsif size < 16384
            [size | 0x80, (size >> 7) & 0x7F].pack("CC")
          else
            [size | 0x80, (size >> 7) | 0x80, (size >> 14) & 0x7F].pack("CCC")
          end
        end

        # Build Huffman encoder from data
        def build_huffman_encoder(data)
          return nil if data.nil? || data.empty?

          # Count byte frequencies
          freq = Array.new(256, 0)
          data.each_byte { |b| freq[b] += 1 }

          # Build Huffman encoder
          HuffmanEncoder.build_from_frequencies(freq, HUFFMAN_MAX_BITS)
        end
      end
    end
  end
end
