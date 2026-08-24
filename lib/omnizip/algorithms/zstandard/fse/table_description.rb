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
      module FSE
        # Reads an FSE table description ("NCount") from the wire and
        # builds an FSE decode Table (RFC 8878 §4.1.1, FSE Table
        # Description; mirrors the C reference FSE_readNCount).
        #
        # The distribution is a forward little-endian bit-packed stream:
        # 4 bits of table log, then per-symbol counts whose bit width
        # shrinks as probability points are spent, with 2-bit repeat
        # codes for runs of zero-count symbols.
        module TableDescription
          include Constants

          MAX_SYMBOL_VALUE = 255

          # rubocop:disable Metrics/MethodLength
          # rubocop:disable Metrics/PerceivedComplexity
          module_function

          # Read a normalized distribution from the head of `src`.
          #
          # @param src [String] bytes holding the table description
          #   (plus whatever follows)
          # @return [Array(Table, Integer)] the decode table and the
          #   number of bytes consumed
          def read(src)
            raise Omnizip::DecompressionError, "FSE table description truncated" if src.bytesize < 4

            reader = BitReader.new(src)

            table_log = (reader.peek & 0xF) + FSE_MIN_ACCURACY_LOG
            if table_log > FSE_MAX_ACCURACY_LOG
              raise Omnizip::DecompressionError,
                    "FSE tableLog #{table_log} exceeds max #{FSE_MAX_ACCURACY_LOG}"
            end
            reader.skip_bits(4)

            remaining = (1 << table_log) + 1
            threshold = 1 << table_log
            nb_bits = table_log + 1

            counts = Array.new(MAX_SYMBOL_VALUE + 1, 0)
            charnum = 0
            previous0 = false

            loop do
              if previous0
                charnum = skip_zero_run(reader, charnum)
                previous0 = false
                break if charnum > MAX_SYMBOL_VALUE

                next
              end

              max = ((2 * threshold) - 1) - remaining
              masked = reader.peek & (threshold - 1)
              if masked < max
                count = masked
                reader.skip_bits(nb_bits - 1)
              else
                count = reader.peek & ((2 * threshold) - 1)
                count -= max if count >= threshold
                reader.skip_bits(nb_bits)
              end

              actual = count - 1
              actual.negative? ? remaining += actual : remaining -= actual
              counts[charnum] = actual
              charnum += 1
              previous0 = actual.zero?

              if remaining < threshold
                break if remaining <= 1

                high = Constants.highbit32(remaining)
                nb_bits = high + 1
                threshold = 1 << high
              end
              break if charnum > MAX_SYMBOL_VALUE
            end

            if remaining != 1
              raise Omnizip::DecompressionError,
                    "FSE distribution does not sum to table size (remaining=#{remaining})"
            end
            if charnum.zero?
              raise Omnizip::DecompressionError, "FSE distribution is empty"
            end

            counts = counts.first(charnum)
            [Table.build(counts, table_log), reader.bytes_consumed]
          end
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/MethodLength

          # Count 2-bit repeat codes after a zero-count symbol.
          def skip_zero_run(reader, charnum)
            inverted = (~reader.peek) | 0x80000000
            repeats = trailing_zeros(inverted) >> 1
            while repeats >= 12
              charnum += 36
              charnum = MAX_SYMBOL_VALUE + 1 if charnum > MAX_SYMBOL_VALUE + 1
              reader.skip_bits(24)
              inverted = (~reader.peek) | 0x80000000
              repeats = trailing_zeros(inverted) >> 1
            end
            charnum += 3 * repeats
            charnum = MAX_SYMBOL_VALUE + 1 if charnum > MAX_SYMBOL_VALUE + 1
            reader.skip_bits(2 * repeats)

            tail = reader.peek & 3
            charnum += tail
            charnum = MAX_SYMBOL_VALUE + 1 if charnum > MAX_SYMBOL_VALUE + 1
            reader.skip_bits(2)

            charnum
          end

          def trailing_zeros(value)
            count = 0
            while value.nobits?(1) && count < 32
              value >>= 1
              count += 1
            end
            count
          end

          # Forward little-endian bit reader over a byte string with a
          # sliding 32-bit window (C FSE_readNCount's bit reader).
          class BitReader
            def initialize(src)
              @src = src
              @byte_pos = 0
              @bit_count = 0
              @bit_window = read_u32(0)
            end

            def peek
              @bit_window
            end

            def skip_bits(bits)
              refill(bits)
            end

            def bytes_consumed
              @byte_pos + ((@bit_count + 7) >> 3)
            end

            private

            def refill(extra_bits)
              @bit_count += extra_bits
              advance = @bit_count >> 3
              if @byte_pos + advance + 4 > @src.bytesize
                # Clamp to the last 4 bytes, as the C reference does.
                new_pos = @src.bytesize - 4
                consumed = (new_pos - @byte_pos) * 8
                @bit_count = (((@bit_count - consumed) % 32) + 32) % 32
                @byte_pos = new_pos
              else
                @byte_pos += advance
                @bit_count &= 7
              end
              @bit_window = read_u32(@byte_pos) >> @bit_count
            end

            def read_u32(offset)
              @src.getbyte(offset) |
                (@src.getbyte(offset + 1) << 8) |
                (@src.getbyte(offset + 2) << 16) |
                (@src.getbyte(offset + 3) << 24)
            end
          end
        end
      end
    end
  end
end
