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
      # Huffman encoder for Zstandard literals (RFC 8878 §4.2).
      #
      # Builds a length-limited Huffman code from per-byte frequencies,
      # emits the weight table (direct or FSE-compressed), and codes
      # the literals into 1 or 4 reverse bitstreams.
      module HuffmanEncoder
        include Constants

        module_function

        # Build 256 weights (0 for absent symbols) from the literal
        # bytes, with code lengths capped at HUFFMAN_MAX_BITS.
        #
        # @param literals [String]
        # @return [Array<Integer>]
        def build_weights(literals)
          counts = Array.new(256, 0)
          literals.each_byte { |b| counts[b] += 1 }

          present = (0..255).select { |b| counts[b].positive? }
          if present.length < 2
            # A Huffman table needs at least 2 symbols; pad with
            # symbol 0 (or 1) so the real symbol keeps a real code.
            weights = Array.new(256, 0)
            sym = present.first || 0
            weights[sym] = 1
            other = sym.zero? ? 1 : 0
            weights[other] = 1
            return weights
          end

          freqs = present.map { |b| counts[b] }
          lengths = huffman_lengths(freqs)
          lengths = limit_lengths(lengths, HUFFMAN_MAX_BITS, freqs)

          max_len = lengths.max
          weights = Array.new(256, 0)
          present.each_with_index do |byte, i|
            weights[byte] = max_len - lengths[i] + 1
          end
          weights
        end

        # Standard Huffman code lengths via smallest-pair merging.
        #
        # @param freqs [Array<Integer>]
        # @return [Array<Integer>] code length per symbol
        def huffman_lengths(freqs)
          nodes = freqs.map { |f| { freq: f, parent: -1 } }

          while nodes.count { |n| n[:parent] == -1 } > 1
            a = -1
            b = -1
            nodes.each_with_index do |n, i|
              next unless n[:parent] == -1

              if a == -1 || n[:freq] < nodes[a][:freq]
                b = a
                a = i
              elsif b == -1 || n[:freq] < nodes[b][:freq]
                b = i
              end
            end

            nodes[a][:parent] = nodes.length
            nodes[b][:parent] = nodes.length
            nodes << { freq: nodes[a][:freq] + nodes[b][:freq], parent: -1 }
          end

          lengths = Array.new(freqs.length, 0)
          freqs.each_index do |i|
            len = 0
            cur = i
            while nodes[cur][:parent] != -1
              cur = nodes[cur][:parent]
              len += 1
            end
            lengths[i] = [len, 255].min
          end
          lengths
        end

        # Cap code lengths at max_len while preserving the Kraft
        # inequality: shorten the longest codes and lengthen the
        # shortest until the sum of 2^-len is <= 1.
        #
        # @param lengths [Array<Integer>] mutated in place
        # @param max_len [Integer]
        # @param freqs [Array<Integer>]
        # @return [Array<Integer>]
        def limit_lengths(lengths, max_len, freqs)
          loop do
            cur_max = lengths.max || 0
            break if cur_max <= max_len

            longest = nil
            lengths.each_with_index do |l, i|
              next unless l == cur_max
              next if longest && freqs[i] >= freqs[longest]

              longest = i
            end

            shortest = nil
            lengths.each_with_index do |l, i|
              next unless l.positive? && l < max_len
              next if shortest && freqs[i] <= freqs[shortest]

              shortest = i
            end

            if longest && shortest
              lengths[longest] -= 1
              lengths[shortest] += 1
            else
              lengths.map! { |l| [l, max_len].min }
              break
            end
          end

          loop do
            kraft = lengths.sum { |l| l.positive? ? 2.0**-l : 0.0 }
            break if kraft <= 1.0 + 1e-10

            min_idx = nil
            lengths.each_with_index do |l, i|
              next unless l.positive? && l < max_len
              next if min_idx && lengths[i] >= lengths[min_idx]

              min_idx = i
            end
            break if min_idx.nil?

            lengths[min_idx] += 1
          end

          lengths
        end

        # Serialize the weight table. Direct 4-bit weights when the
        # alphabet fits, FSE-compressed otherwise.
        #
        # @param weights [Array<Integer>]
        # @return [String]
        def encode_weights(weights)
          max_symbol = weights.rindex(&:positive?)
          raise Omnizip::CompressionError, "no present Huffman weights" if max_symbol.nil?

          if max_symbol <= 128
            encode_weights_direct(weights, max_symbol)
          else
            encode_weights_fse(weights, max_symbol)
          end
        end

        # Direct encoding: header byte 127 + o_size, then two 4-bit
        # weights per byte. The last present weight is implied on
        # decode and is dropped here.
        def encode_weights_direct(weights, max_symbol)
          o_size = max_symbol
          i_size = 127 + o_size
          out = [i_size].pack("C")

          (0...o_size).step(2) do |n|
            high = weights[n] & 0x0F
            low = n + 1 < o_size ? weights[n + 1] & 0x0F : 0
            out << ((high << 4) | low).chr
          end

          out
        end

        # FSE-compressed weights (RFC 8878 §4.2.1.2): payload-size
        # header byte, NCount, then the 2-state bitstream.
        def encode_weights_fse(weights, max_symbol)
          o_size = max_symbol
          symbols = weights.first(o_size)

          distinct = symbols.uniq.length
          if distinct <= 1
            raise Omnizip::CompressionError,
                  "uniform Huffman weights give no compression"
          end

          encoder = FSE::Encoder.build_from_symbols(symbols, 11, 6)
          if encoder.nil?
            raise Omnizip::CompressionError,
                  "uniform Huffman weights give no compression"
          end

          payload = encoder.compress(symbols)
          if payload.bytesize >= 128
            raise Omnizip::CompressionError,
                  "FSE weight payload exceeds the 127-byte header limit"
          end

          [payload.bytesize].pack("C") + payload
        end

        # Encode literals as a Compressed_Literals_Block section:
        # header + weights + coded stream(s).
        #
        # @param literals [String]
        # @return [String]
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/AbcSize
        def encode_literals(literals)
          weights = build_weights(literals)
          # The wire format drops the last present weight (it is implied
          # by the Kraft inequality on decode), so the coding table must
          # be rebuilt exactly the way the decoder rebuilds it.
          max_symbol = weights.rindex(&:positive?)
          wire_weights = weights.first(max_symbol)
          full_weights = wire_weights +
            [HuffmanTableReader.implied_last_weight(wire_weights)]
          table = Huffman.from_weights(full_weights)
          encode_table = table.encode_table

          weights_wire = encode_weights(weights)
          lit_size = literals.bytesize

          # Single stream (3-byte header) when both sizes fit 10 bits.
          if lit_size < 1024
            coded = encode_huffman_stream(encode_table, literals)
            lit_c_size = weights_wire.bytesize + coded.bytesize
            if lit_c_size < 1024
              header = LITERALS_BLOCK_COMPRESSED |
                (lit_size << 4) | (lit_c_size << 14)
              return [header].pack("V")[0, 3] + weights_wire + coded
            end
          end

          # 4 streams with a jump table.
          segment_size = (lit_size + 3) / 4
          segments = Array.new(4) do |i|
            encode_huffman_stream(
              encode_table,
              literals.byteslice(segment_size * i, segment_size),
            )
          end

          lit_c_size = weights_wire.bytesize + 6 + segments.sum(&:bytesize)

          out = if lit_size < 1024 && lit_c_size < 1024
                  header = LITERALS_BLOCK_COMPRESSED | (0b01 << 2) |
                    (lit_size << 4) | (lit_c_size << 14)
                  [header].pack("V")[0, 3]
                elsif lit_size < 16_384 && lit_c_size < 16_384
                  header = LITERALS_BLOCK_COMPRESSED | (0b10 << 2) |
                    (lit_size << 4) | (lit_c_size << 18)
                  [header].pack("V")[0, 4]
                elsif lit_size < 262_144 && lit_c_size < 262_144
                  low = LITERALS_BLOCK_COMPRESSED | (0b11 << 2) |
                    (lit_size << 4) | ((lit_c_size & 0x3FF) << 22)
                  [low].pack("V") + [(lit_c_size >> 10) & 0xFF].pack("C")
                else
                  raise Omnizip::CompressionError,
                        "literals section exceeds the 18-bit header limits"
                end

          out + weights_wire +
            segments.first(3).map { |s| [s.bytesize].pack("v") }.join +
            segments.join
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        # Code literals into one reverse bitstream (C BIT_CStream
        # direction): the encoder writes the last symbol first so the
        # reverse reader recovers symbols in order.
        #
        # @param encode_table [Array<Array(Integer, Integer)>]
        # @param literals [String]
        # @return [String]
        def encode_huffman_stream(encode_table, literals)
          bitc = FSE::Encoder::BitCStream.new
          (literals.bytesize - 1).downto(0) do |i|
            code, len = encode_table[literals.getbyte(i)]
            next if len.zero?

            bitc.add_bits(code, len)
            bitc.flush
          end
          bitc.close
        end
      end
    end
  end
end
