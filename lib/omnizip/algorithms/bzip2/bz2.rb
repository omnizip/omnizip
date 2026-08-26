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
    class BZip2
      # Standard bzip2 wire format (port of the omnizip-rs
      # omnizip-bzip2/src/bz2 module).
      #
      # Output is decodable by `bzip2 -d`; input from the bzip2 CLI
      # decodes here. Pipeline: RLE1 -> BWT -> seeded MTF -> RLE2
      # (RUNA/RUNB) -> canonical Huffman, MSB-first bit packing, with
      # the bzip2 CRC-32 variant on every block and a combined
      # stream CRC.
      module Bz2
        BLOCK_MAGIC = 0x3141_5926_5359
        EOS_MAGIC = 0x1772_4538_5090
        N_GROUPS = 2
        GROUP_SIZE = 50
        MAX_GROUPS = 6
        MAX_CODE_LENGTH = 23
        RUNA = 0
        RUNB = 1

        module_function

        # bzip2 CRC-32: non-reflected polynomial 0x04C11DB7, init
        # 0xFFFFFFFF, final complement — NOT the zlib variant.
        def crc32(data)
          table = CRC_TABLE
          crc = 0xFFFF_FFFF
          data.each_byte do |b|
            crc = ((crc << 8) & 0xFFFF_FFFF) ^
              table[((crc >> 24) ^ b) & 0xFF]
          end
          crc ^ 0xFFFF_FFFF
        end

        CRC_TABLE = Array.new(256) do |i|
          crc = i << 24
          8.times do
            crc = if crc.nobits?(0x8000_0000)
                    (crc << 1) & 0xFFFF_FFFF
                  else
                    ((crc << 1) ^ 0x04C1_1DB7) & 0xFFFF_FFFF
                  end
          end
          crc
        end

        # Compress `input` into a standard .bz2 stream. `level`
        # (1-9) selects the block size in 100 KB steps.
        def compress(input, level = 9)
          raise Omnizip::CompressionError, "bzip2 level must be 1..9" unless (1..9).cover?(level)

          block_size = level * 100_000
          writer = BitWriter.new
          writer.write_bits("B".ord, 8)
          writer.write_bits("Z".ord, 8)
          writer.write_bits("h".ord, 8)
          writer.write_bits("0".ord + level, 8)

          if input.empty?
            writer.write48(EOS_MAGIC)
            writer.write_bits(0, 32)
            return writer.finish
          end

          combined = 0
          offset = 0
          while offset < input.bytesize
            chunk = input.byteslice(offset, block_size)
            offset += block_size
            block_crc = crc32(chunk)
            combined = rotate_left32(combined, 1) ^ block_crc
            encode_block(chunk, block_crc, writer)
          end
          writer.write48(EOS_MAGIC)
          writer.write_bits(combined, 32)
          writer.finish
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def encode_block(block, block_crc, writer)
          rle1 = Rle.new.encode(block)
          bwt_data, primary_index = Bwt.new.encode(rle1)
          sequence = build_sequence(bwt_data)
          n_in_use = sequence.length
          mtf = mtf_encode_seeded(bwt_data, sequence)
          symbols = mtf_to_symbols(mtf, n_in_use)
          alphabet_size = n_in_use + 2

          writer.write48(BLOCK_MAGIC)
          writer.write_bits(block_crc, 32)
          writer.write_bit(false) # never randomised
          writer.write_bits(primary_index & 0xFF_FFFF, 24)

          groups_used, group_maps = build_symbol_map(bwt_data)
          writer.write_bits(groups_used, 16)
          group_maps.each { |g| writer.write_bits(g, 16) }

          # Assign every GROUP_SIZE-symbol chunk to the lowest-
          # frequency table (classic bzip2 selector algorithm).
          chunks = symbols.each_slice(GROUP_SIZE).to_a
          table_freqs = Array.new(N_GROUPS) { Array.new(alphabet_size, 0) }
          selectors = []
          chunks.each do |chunk|
            chunk_freq = Array.new(alphabet_size, 0)
            chunk.each { |s| chunk_freq[s] += 1 }
            best = (0...N_GROUPS).min_by do |i|
              chunk_freq.zip(table_freqs[i]).sum { |a, b| a + b }
            end
            selectors << best
            alphabet_size.times { |a| table_freqs[best][a] += chunk_freq[a] }
          end

          # MTF the selectors (Rust mirrors upstream bzip2).
          order = (0...N_GROUPS).to_a
          mtf_selectors = selectors.map do |t|
            idx = order.index(t)
            order.delete_at(idx)
            order.unshift(t)
            idx
          end

          n_selectors = [chunks.length, 1].max
          writer.write_bits(N_GROUPS, 3)
          writer.write_bits(n_selectors, 15)
          # MTF value N -> N '1's then '0'.
          mtf_selectors.each do |v|
            v.times { writer.write_bit(true) }
            writer.write_bit(false)
          end

          # Build N canonical-Huffman tables over the alphabet.
          lengths_per_table = Array.new(N_GROUPS) { |i| code_lengths(table_freqs[i]) }
          tables = lengths_per_table.map { |l| canonical_codes(l) }

          lengths_per_table.each { |l| write_huffman_table(writer, l) }

          chunks.each_with_index do |chunk, i|
            table = tables[selectors[i]]
            chunk.each do |sym|
              code, len = table[sym]
              writer.write_bits(code, len)
            end
          end
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        # The active bytes in ascending order (the seeded-MTF table).
        def build_sequence(data)
          seen = Array.new(256, false)
          data.each_byte { |b| seen[b] = true }
          (0...256).select { |b| seen[b] }
        end

        # rubocop:disable Metrics/MethodLength
        def mtf_encode_seeded(data, sequence)
          table = sequence.dup
          out = []
          data.each_byte do |byte|
            pos = table.index(byte)
            out << pos
            table.delete_at(pos)
            table.unshift(byte)
          end
          out
        end

        # RUNA/RUNB (bijective base-2) zero-run encoding plus the
        # value/EOB symbols; EOB = n_in_use + 1.
        # rubocop:disable-next Metrics/AbcSize
        def mtf_to_symbols(mtf_values, n_in_use)
          eob = n_in_use + 1
          out = []
          i = 0
          while i < mtf_values.length
            v = mtf_values[i]
            if v.zero?
              run = 0
              while i < mtf_values.length && mtf_values[i].zero?
                run += 1
                i += 1
              end
              n = run
              while n.positive?
                n -= 1
                out << (n.nobits?(1) ? RUNA : RUNB)
                n >>= 1
              end
            else
              out << (v + 1)
              i += 1
            end
          end
          out << eob
          out
        end
        # rubocop:enable Metrics/MethodLength

        # bzip2 symbol usage map: 16-bit group word, then one 16-bit
        # byte map per used group (bit 15 - index, MSB-first order).
        # rubocop:disable-next Metrics/AbcSize
        def build_symbol_map(data)
          used = Array.new(256, false)
          data.each_byte { |b| used[b] = true }

          groups_used = 0
          detail = []
          16.times do |g|
            group_bits = 0
            any = false
            16.times do |j|
              next unless used[(g * 16) + j]

              group_bits |= 1 << (15 - j)
              any = true
            end
            next unless any

            groups_used |= 1 << (15 - g)
            detail << group_bits
          end
          [groups_used, detail]
        end

        # Canonical Huffman code lengths (every symbol gets a code;
        # zero frequencies become 1) with rescaling to keep lengths
        # within bzip2's 23-bit limit.
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        def code_lengths(freqs)
          n = freqs.length
          active = freqs.each_index.map { |i| [(freqs[i].zero? ? 1 : freqs[i]), i] }
          return Array.new(n, 0) if active.empty?

          loop do
            lengths = huffman_lengths(active, n)
            max_len = lengths.max || 0
            return lengths if max_len <= MAX_CODE_LENGTH

            scaled = false
            active.map! do |(w, i)|
              if w > 1
                scaled = true
                [(w + 1) / 2, i]
              else
                [w, i]
              end
            end
            # Can't reduce further: clamp.
            return lengths.map { |l| [l, MAX_CODE_LENGTH].min } unless scaled
          end
        end

        # Standard Huffman via smallest-pair merging with parent
        # pointers; depth = code length per active symbol.
        # rubocop:disable-next Metrics/AbcSize
        def huffman_lengths(active, alphabet_size)
          nodes = active.map { |(w, _i)| { freq: w, parent: -1 } }
          ids = active.map { |_w, i| i }
          next_id = alphabet_size

          loop do
            roots = []
            nodes.each_index { |k| roots << k if nodes[k][:parent] == -1 }
            break if roots.length <= 1

            a = -1
            b = -1
            roots.each do |k|
              if a == -1 || nodes[k][:freq] < nodes[a][:freq] ||
                  (nodes[k][:freq] == nodes[a][:freq] && ids[k] < ids[a])
                b = a
                a = k
              elsif b == -1 || nodes[k][:freq] < nodes[b][:freq] ||
                  (nodes[k][:freq] == nodes[b][:freq] && ids[k] < ids[b])
                b = k
              end
            end

            nodes[a][:parent] = nodes.length
            nodes[b][:parent] = nodes.length
            nodes << { freq: nodes[a][:freq] + nodes[b][:freq], parent: -1 }
            ids << next_id
            next_id += 1
          end

          out = Array.new(alphabet_size, 0)
          active.each_index do |k|
            sym = ids[k]
            len = 0
            cur = k
            while nodes[cur][:parent] != -1
              cur = nodes[cur][:parent]
              len += 1
            end
            out[sym] = [len, 1].max
          end
          out
        end

        # Canonical codes assigned in (length, symbol) order.
        # rubocop:disable-next Metrics/AbcSize
        def canonical_codes(lengths)
          max_len = lengths.max || 0
          codes = Array.new(lengths.length) { [0, 0] }
          return codes if max_len.zero?

          bl_count = Array.new(max_len + 1, 0)
          lengths.each { |l| bl_count[l] += 1 if l.positive? }

          next_code = Array.new(max_len + 1, 0)
          code = 0
          (1..max_len).each do |bits|
            code = (code + bl_count[bits - 1]) << 1
            next_code[bits] = code
          end
          lengths.each_with_index do |len, sym|
            next unless len.positive?

            codes[sym] = [next_code[len], len]
            next_code[len] += 1
          end
          codes
        end

        # Delta-coded code-length table: 5-bit start length, then
        # '10' (+1) / '11' (-1) adjustments and a '0' terminator per
        # symbol.
        def write_huffman_table(writer, lengths)
          writer.write_bits(lengths[0], 5)
          current = lengths[0]
          lengths.each do |target|
            diff = target - current
            while diff != 0
              writer.write_bit(true)
              if diff.positive?
                writer.write_bit(false)
                diff -= 1
                current += 1
              else
                writer.write_bit(true)
                diff += 1
                current -= 1
              end
            end
            writer.write_bit(false)
          end
        end
        # rubocop:enable Metrics/MethodLength

        def rotate_left32(v, n)
          ((v << n) | (v >> (32 - n))) & 0xFFFF_FFFF
        end

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable-next Metrics/AbcSize
        # Decompress a complete .bz2 stream (single member). Verifies
        # every block CRC and the combined stream CRC.
        def decompress(input)
          if input.bytesize < 4 || input.byteslice(0, 3) != "BZh" ||
              !input.getbyte(3).between?("0".ord, "9".ord)
            raise Omnizip::DecompressionError, "not a bzip2 stream (bad header)"
          end

          r = BitReader.new(input, 4)
          out = String.new(encoding: Encoding::BINARY)
          combined = 0
          # rubocop:disable-next Metrics/BlockLength
          loop do
            magic = r.read48
            if magic == EOS_MAGIC
              stored = r.read_bits(32)
              if stored != combined
                raise Omnizip::DecompressionError,
                      format("combined CRC mismatch: stored %08X, " \
                             "computed %08X", stored, combined)
              end
              return out
            end
            unless magic == BLOCK_MAGIC
              raise Omnizip::DecompressionError,
                    format("bad block magic %012X", magic)
            end

            block_crc = r.read_bits(32)
            if r.read_bit == 1
              raise Omnizip::DecompressionError,
                    "randomised blocks are not supported"
            end
            orig_ptr = r.read_bits(24)

            groups = r.read_bits(16)
            if groups.zero?
              raise Omnizip::DecompressionError, "empty symbol map"
            end

            sequence = []
            16.times do |g|
              next unless groups.anybits?(1 << (15 - g))

              map = r.read_bits(16)
              16.times do |b|
                sequence << ((g * 16) + b) if map.anybits?(1 << (15 - b))
              end
            end
            n_in_use = sequence.length

            n_groups = r.read_bits(3)
            unless (2..MAX_GROUPS).cover?(n_groups)
              raise Omnizip::DecompressionError, "invalid nGroups #{n_groups}"
            end

            n_selectors = r.read_bits(15)
            if n_selectors.zero?
              raise Omnizip::DecompressionError, "zero selectors"
            end

            selector_mtf = []
            n_selectors.times do
              j = 0
              while r.read_bit == 1
                j += 1
                if j > MAX_GROUPS
                  raise Omnizip::DecompressionError,
                        "selector unary run too long"
                end
              end
              selector_mtf << j
            end
            order = (0...n_groups).to_a
            selectors = selector_mtf.map do |j|
              table = order.delete_at(j)
              order.unshift(table)
              table
            end

            alphabet = n_in_use + 2
            tables = Array.new(n_groups) do
              lengths = Array.new(alphabet, 0)
              cur = r.read_bits(5)
              alphabet.times do |slot|
                loop do
                  break if r.read_bit.zero?

                  cur += r.read_bit == 1 ? -1 : 1
                end
                lengths[slot] = cur
              end
              build_table(lengths)
            end

            eob = n_in_use + 1
            symbols = []
            catch(:eob) do
              selectors.each do |sel|
                table = tables[sel]
                GROUP_SIZE.times do
                  sym = decode_symbol(table, r)
                  throw :eob if sym == eob

                  symbols << sym
                end
              end
            end

            mtf = symbols_to_mtf(symbols, n_in_use)
            bwt = mtf_decode_seeded(mtf, sequence)
            block = Bwt.new.decode(bwt, orig_ptr)
            data = Rle.new.decode(block)
            computed = crc32(data)
            if computed != block_crc
              raise Omnizip::DecompressionError,
                    format("block CRC mismatch: stored %08X, " \
                           "computed %08X", block_crc, computed)
            end
            combined = rotate_left32(combined, 1) ^ block_crc
            out << data
          end
        end
        # rubocop:enable Metrics/MethodLength

        # RUNA/RUNB symbol stream back to MTF values.
        # rubocop:disable-next Metrics/AbcSize
        def symbols_to_mtf(symbols, n_in_use)
          eob = n_in_use + 1
          mtf = []
          i = 0
          while i < symbols.length
            sym = symbols[i]
            if [RUNA, RUNB].include?(sym)
              run = 0
              bit = 1
              while i < symbols.length && [RUNA, RUNB].include?(symbols[i])
                run += symbols[i] == RUNB ? bit << 1 : bit
                bit <<= 1
                i += 1
              end
              [run, 1 << 24].min.times { mtf << 0 }
            elsif sym == eob
              break
            else
              mtf << (sym - 1)
              i += 1
            end
          end
          mtf
        end

        # Seed-aware MTF inverse over the active-byte sequence.
        # Returns a binary String (the BWT stage consumes bytes).
        def mtf_decode_seeded(data, sequence)
          list = sequence.dup
          out = Array.new(data.length)
          data.each_with_index do |v, i|
            if v >= list.length
              out[i] = 0
            else
              b = list.delete_at(v)
              list.unshift(b)
              out[i] = b
            end
          end
          out.pack("C*")
        end

        # Canonical code table: entries sorted for bit-by-bit match.
        def build_table(lengths)
          alphabet = lengths.length
          order = (0...alphabet).sort_by { |i| [lengths[i], i] }
          entries = []
          code = 0
          length = 0
          order.each do |i|
            while length < lengths[i]
              code <<= 1
              length += 1
            end
            next unless lengths[i].positive?

            entries << [i, code, lengths[i]]
            code += 1
          end
          entries
        end

        def decode_symbol(table, r)
          code = 0
          len = 0
          loop do
            code = (code << 1) | r.read_bit
            len += 1
            raise Omnizip::DecompressionError, "huffman code too long" if len > 24

            table.each do |(sym, c, l)|
              return sym if l == len && c == code
            end
          end
        end

        # MSB-first bit reader.
        class BitReader
          def initialize(data, pos = 0)
            @data = data
            @pos = pos
            @bits = 0
            @nbits = 0
          end

          def read_bit
            if @nbits.zero?
              raise Omnizip::DecompressionError, "unexpected end of bitstream" if @pos >= @data.bytesize

              @bits = @data.getbyte(@pos)
              @pos += 1
              @nbits = 8
            end
            @nbits -= 1
            @bits.nobits?(1 << @nbits) ? 0 : 1
          end

          def read_bits(n)
            v = 0
            n.times { v = (v << 1) | read_bit }
            v
          end

          def read48
            (read_bits(24) << 24) | read_bits(24)
          end
        end

        # MSB-first bit packer.
        class BitWriter
          def initialize
            @out = []
            @current = 0
            @nbits = 0
          end

          def write_bits(bits, n)
            return if n.zero?

            mask = n == 32 ? bits : bits & ((1 << n) - 1)
            @current = ((@current << n) | mask) & 0xFFFF_FFFF_FFFF_FFFF
            @nbits += n
            while @nbits >= 8
              @nbits -= 8
              @out << ((@current >> @nbits) & 0xFF)
            end
          end

          def write_bit(bit)
            write_bits(bit ? 1 : 0, 1)
          end

          def write48(value)
            write_bits(value >> 24, 24)
            write_bits(value & 0xFF_FFFF, 24)
          end

          def finish
            if @nbits.positive?
              @out << ((@current << (8 - @nbits)) & 0xFF)
              @nbits = 0
            end
            @out.pack("C*")
          end
        end
      end
    end
  end
end
