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
      # Huffman coding for Zstandard literals (RFC 8878 §4.2).
      #
      # Zstandard does NOT use symbol-ordered canonical Huffman. The
      # decode table groups symbols by weight: all weight-1 symbols
      # occupy the first DTable entries, then weight-2, and so on, with
      # ascending symbol order inside each group. A symbol with weight
      # w has code length (tableLog + 1 - w) and occupies (1 << w) >> 1
      # consecutive DTable entries.
      class Huffman
        include Constants

        DecodeEntry = Struct.new(:symbol, :nb_bits)

        # @return [Array<Integer>] per-symbol weights (0 = absent)
        attr_reader :weights

        # @return [Integer] table log (max code length in this tree)
        attr_reader :table_log

        # Build a decode table from per-symbol weights.
        #
        # @param weights [Array<Integer>] one entry per symbol
        # @return [Huffman]
        def self.from_weights(weights)
          table_log = compute_table_log(weights)
          new(weights, table_log)
        end

        def initialize(weights, table_log)
          @weights = weights
          @table_log = table_log
          @lookup = nil
        end

        # Decode one symbol from a reverse bitstream (peek max_bits,
        # look up, consume the code's length).
        #
        # @param bitstream [FSE::BitStream]
        # @return [Integer] decoded symbol byte
        def decode(bitstream)
          entry = lookup[bitstream.peek_bits(HUFFMAN_MAX_BITS)]
          if entry.nil? || entry.nb_bits.zero?
            raise Omnizip::DecompressionError,
                  "Huffman lookup miss: no code for the next bits"
          end

          bitstream.read_bits(entry.nb_bits)
          entry.symbol
        end

        # Build the flat 1 << HUFFMAN_MAX_BITS lookup table.
        #
        # @return [Array<DecodeEntry>]
        def lookup
          @lookup ||= begin
            table_size = 1 << @table_log
            dtable = Array.new(table_size) { DecodeEntry.new(0, 0) }
            max_weight = @weights.max || 0

            pos = 0
            (1..max_weight).each do |w|
              length = @table_log + 1 - w
              entries_per_symbol = (1 << w) >> 1
              @weights.each_with_index do |sw, sym|
                next unless sw == w

                entry = DecodeEntry.new(sym, length)
                entries_per_symbol.times do
                  if pos < table_size
                    dtable[pos] = entry
                    pos += 1
                  end
                end
              end
            end

            expand = 1 << (HUFFMAN_MAX_BITS - @table_log)
            lookup = []
            table_size.times do |i|
              expand.times { lookup << dtable[i] }
            end
            while lookup.length < (1 << HUFFMAN_MAX_BITS)
              lookup << DecodeEntry.new(0, 0)
            end
            lookup
          end
        end

        # Per-symbol (code, length) table for encoding, indexed by
        # symbol value. Absent symbols map to (0, 0).
        #
        # @return [Array<Array(Integer, Integer)>]
        def encode_table
          @encode_table ||= begin
            codes = Array.new(@weights.length) { [0, 0] }
            max_weight = @weights.max || 0
            dtable_pos = 0
            (1..max_weight).each do |w|
              length = @table_log + 1 - w
              entries_per_symbol = (1 << w) >> 1
              @weights.each_with_index do |sw, sym|
                next unless sw == w

                code = dtable_pos >> (@table_log - length)
                codes[sym] = [code, length]
                dtable_pos += entries_per_symbol
              end
            end
            codes.fill([0, 0], codes.length..255)
            codes
          end
        end

        # Derive tableLog from the Kraft sum of the weights
        # (C reference HUF_readStats).
        #
        # @return [Integer]
        def self.compute_table_log(weights)
          if weights.empty? || weights.all?(0)
            raise Omnizip::DecompressionError,
                  "Huffman weights: no present symbols"
          end

          weight_total = weights.sum { |w| w.positive? ? (1 << w) >> 1 : 0 }
          if weight_total.zero?
            raise Omnizip::DecompressionError, "Huffman weight total is 0"
          end

          table_log = if weight_total.nobits?(weight_total - 1)
                        Constants.highbit32(weight_total)
                      else
                        Constants.highbit32(weight_total) + 1
                      end
          if table_log > HUFFMAN_MAX_BITS
            raise Omnizip::DecompressionError,
                  "Huffman tableLog #{table_log} exceeds max #{HUFFMAN_MAX_BITS}"
          end

          table_log
        end
      end

      # Reads a Huffman tree description from the wire (RFC 8878
      # §4.2.1) and builds a Huffman decode table.
      class HuffmanTableReader
        include Constants

        # Read the table from the head of `src`.
        #
        # @param src [String]
        # @return [Array(Huffman, Integer)] table and bytes consumed
        def self.read(src)
          raise Omnizip::DecompressionError, "empty Huffman header" if src.empty?

          i_size = src.getbyte(0)
          weights, consumed =
            if i_size >= 128
              read_direct_weights(src)
            else
              read_fse_compressed_weights(src)
            end

          [Huffman.from_weights(weights), consumed]
        end

        # Direct 4-bit weights: byte 0 is 127 + o_size, then
        # (o_size + 1) / 2 bytes holding two nibbles each.
        def self.read_direct_weights(src)
          i_size = src.getbyte(0)
          o_size = i_size - 127
          packed_bytes = (o_size + 1) / 2
          needed = 1 + packed_bytes
          if src.bytesize < needed
            raise Omnizip::DecompressionError,
                  "truncated direct Huffman weights: need #{needed} bytes"
          end

          weights = []
          (0...o_size).step(2) do |n|
            byte = src.getbyte(1 + (n / 2))
            weights << (byte >> 4)
            weights << (byte & 0x0F) if n + 1 < o_size
          end

          weights << implied_last_weight(weights)
          [weights, needed]
        end

        # FSE-compressed weights: byte 0 is the payload size, followed
        # by an FSE table description and a 2-state interleaved
        # bitstream (RFC 8878 §4.2.1.2).
        def self.read_fse_compressed_weights(src)
          i_size = src.getbyte(0)
          if 1 + i_size > src.bytesize
            raise Omnizip::DecompressionError,
                  "truncated FSE Huffman weights: need #{1 + i_size} bytes"
          end

          payload = src.byteslice(1, i_size)
          table, consumed = FSE.read_table(payload)
          bitstream = payload.byteslice(consumed..)

          weights = FSE.decode_stream(table, bitstream, HUF_SYMBOLVALUE_MAX)
          weights << implied_last_weight(weights)
          [weights, 1 + i_size]
        end

        # Compute the implied last weight via the Kraft inequality:
        # sum(2^(w-1)) over all symbols equals 1 << tableLog.
        def self.implied_last_weight(weights)
          weight_total = 0
          weights.each do |w|
            if w > HUFFMAN_MAX_LOG
              raise Omnizip::DecompressionError,
                    "Huffman weight #{w} exceeds tableLog max"
            end

            weight_total += (1 << w) >> 1
          end
          if weight_total.zero?
            raise Omnizip::DecompressionError, "Huffman weights sum to 0"
          end

          table_log = Constants.highbit32(weight_total) + 1
          if table_log > HUFFMAN_MAX_LOG
            raise Omnizip::DecompressionError,
                  "Huffman tableLog #{table_log} exceeds max"
          end

          rest = (1 << table_log) - weight_total
          if rest.zero?
            raise Omnizip::DecompressionError,
                  "Huffman weights already complete; no implied weight"
          end
          unless rest.nobits?(rest - 1)
            raise Omnizip::DecompressionError,
                  "Huffman implied weight remainder #{rest} is not a power of 2"
          end

          last_weight = Constants.highbit32(rest) + 1
          if last_weight > HUFFMAN_MAX_LOG
            raise Omnizip::DecompressionError,
                  "Huffman implied weight #{last_weight} exceeds max"
          end

          last_weight
        end
      end
    end
  end
end
