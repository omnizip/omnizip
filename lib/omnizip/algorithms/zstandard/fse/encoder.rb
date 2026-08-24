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
        # FSE encoder (RFC 8878 §4.1): count normalization, NCount
        # writing, CTable construction, and 2-state interleaved
        # bitstream encoding. Mirrors the C reference FSE library.
        class Encoder
          include Constants

          RTB_TABLE = [0, 473_195, 504_333, 520_860, 550_000, 700_000,
                       750_000, 830_000].freeze
          NOT_YET_ASSIGNED = -2

          SymbolTT = Struct.new(:delta_nb_bits, :delta_find_state)

          # @return [Array<Integer>] normalized distribution
          attr_reader :distribution

          # @return [Integer]
          attr_reader :table_log

          # @return [Integer]
          attr_reader :max_symbol_value

          # Normalize a raw histogram to sum to (1 << table_log).
          #
          # @param table_log [Integer]
          # @param count [Array<Integer>] raw frequencies
          # @param total [Integer] sum(count)
          # @param max_symbol_value [Integer] highest symbol index
          # @param use_low_prob [Boolean] emit -1 sentinels for rare
          #   symbols (the zstd default)
          # @return [Array<Integer>] normalized distribution, or [] for
          #   an RLE stream
          def self.normalize_count(table_log, count, total, max_symbol_value,
                                   use_low_prob: true)
            table_log = FSE_DEFAULT_TABLELOG if table_log.zero?

            norm = Array.new(max_symbol_value + 1, 0)

            # RLE: a single symbol accounts for everything.
            (0..max_symbol_value).each do |s|
              return [] if count[s] == total
            end

            low_prob_count = use_low_prob ? -1 : 1
            scale = 62 - table_log
            step = (1 << 62) / total
            v_step = 1 << (scale - 20)
            still_to_distribute = 1 << table_log
            low_threshold = total >> table_log
            largest = 0
            largest_p = 0

            (0..max_symbol_value).each do |s|
              if count[s].zero?
                norm[s] = 0
                next
              end

              c64 = count[s]
              if c64 <= low_threshold
                norm[s] = low_prob_count
                still_to_distribute -= 1
              else
                proba = (c64 * step) >> scale
                if proba < 8
                  rest_to_beat = v_step * RTB_TABLE[proba]
                  diff = (c64 * step) - (proba << scale)
                  proba += 1 if diff > rest_to_beat
                end
                if proba > largest_p
                  largest_p = proba
                  largest = s
                end
                norm[s] = proba
                still_to_distribute -= proba
              end
            end

            if -still_to_distribute >= norm[largest] / 2
              normalize_m2(norm, table_log, count, total, max_symbol_value,
                           low_prob_count)
            else
              norm[largest] += still_to_distribute
            end

            norm
          end

          # Secondary normalization (C FSE_normalizeM2), used when the
          # primary method's largest-symbol correction would be too big.
          # rubocop:disable Metrics/MethodLength
          # rubocop:disable-next Metrics/AbcSize
          def self.normalize_m2(norm, table_log, count, total, max_symbol_value,
                                low_prob_count)
            table_size = 1 << table_log
            low_threshold = total >> table_log
            low_one = (total * 3) >> (table_log + 1)
            distributed = 0
            remaining = total

            (0..max_symbol_value).each do |s|
              if count[s].zero?
                norm[s] = 0
              elsif count[s] <= low_threshold
                norm[s] = low_prob_count
                distributed += 1
                remaining -= count[s]
              elsif count[s] <= low_one
                norm[s] = 1
                distributed += 1
                remaining -= count[s]
              else
                norm[s] = NOT_YET_ASSIGNED
              end
            end

            to_distribute = table_size - distributed
            return if to_distribute.zero?

            if remaining / to_distribute > low_one
              low_one = (remaining * 3) / (to_distribute * 2)
              (0..max_symbol_value).each do |s|
                if norm[s] == NOT_YET_ASSIGNED && count[s] <= low_one
                  norm[s] = 1
                  distributed += 1
                  remaining -= count[s]
                end
              end
              to_distribute = table_size - distributed
            end

            if distributed == max_symbol_value + 1
              max_v = 0
              max_c = 0
              (0..max_symbol_value).each do |s|
                if count[s] > max_c
                  max_v = s
                  max_c = count[s]
                end
              end
              norm[max_v] += to_distribute
              return
            end

            if remaining.zero?
              idx = 0
              while to_distribute.positive? && idx <= max_symbol_value
                if norm[idx]&.positive?
                  norm[idx] += 1
                  to_distribute -= 1
                end
                idx = (idx + 1) % (max_symbol_value + 1)
              end
              return
            end

            v_step_log = 62 - table_log
            mid = (1 << (v_step_log - 1)) - 1
            r_step = (((1 << v_step_log) * to_distribute) + mid) / remaining
            tmp_total = mid
            (0..max_symbol_value).each do |s|
              next unless norm[s] == NOT_YET_ASSIGNED

              end_v = tmp_total + (count[s] * r_step)
              weight = (end_v >> v_step_log) - (tmp_total >> v_step_log)
              norm[s] = weight
              tmp_total = end_v
            end
          end
          # rubocop:enable Metrics/MethodLength

          # Choose an accuracy log for the given source size and alphabet.
          #
          # Direct port of C FSE_optimalTableLog; the branch ladder is
          # inherent to the algorithm.
          # rubocop:disable-next Metrics/AbcSize
          def self.optimal_table_log(max_table_log, src_size, max_symbol_value)
            return FSE_MIN_ACCURACY_LOG if src_size <= 1

            max_bits_src = (src_size - 1).bit_length - 1 - 2
            max_bits_src = 0 if max_bits_src.negative?
            min_bits_src = src_size.bit_length + 1
            min_bits_sym = [max_symbol_value, 1].max.bit_length + 2
            min_bits = [min_bits_src, min_bits_sym].min

            table_log = max_table_log
            table_log = FSE_DEFAULT_TABLELOG if table_log.zero?
            table_log = max_bits_src if max_bits_src < table_log
            table_log = min_bits if min_bits > table_log
            table_log.clamp(FSE_MIN_ACCURACY_LOG, FSE_MAX_ACCURACY_LOG)
          end

          # Build from raw symbols: normalize + store.
          #
          # @param symbols [Array<Integer>]
          # @param max_symbol_value [Integer]
          # @param max_table_log [Integer]
          # @return [Encoder, nil] nil for an RLE stream (single symbol)
          def self.build_from_symbols(symbols, max_symbol_value,
                                      max_table_log = FSE_DEFAULT_TABLELOG)
            counts = Array.new(max_symbol_value + 1, 0)
            symbols.each { |s| counts[s] += 1 }
            total = symbols.length

            actual_max = max_symbol_value
            actual_max -= 1 while actual_max.positive? && counts[actual_max].zero?

            table_log = optimal_table_log(max_table_log, total, actual_max)
            norm = normalize_count(table_log, counts, total, actual_max,
                                   use_low_prob: true)
            return nil if norm.empty?

            new(norm, table_log, actual_max)
          end

          def initialize(distribution, table_log, max_symbol_value)
            @distribution = distribution
            @table_log = table_log
            @max_symbol_value = max_symbol_value
            build_encoding_tables
          end

          # Serialize the table description (NCount) per RFC 8878 §4.1.1.
          #
          # @return [String]
          # rubocop:disable Metrics/MethodLength
          # rubocop:disable-next Metrics/AbcSize
          def write_ncount
            out = []
            table_size = 1 << @table_log
            bit_stream = 0
            bit_count = 0
            symbol = 0
            alphabet_size = @max_symbol_value + 1
            previous_is_zero = false
            remaining = table_size + 1
            threshold = table_size
            nb_bits = @table_log + 1

            bit_stream |= (@table_log - FSE_MIN_ACCURACY_LOG) << bit_count
            bit_count += 4

            while symbol < alphabet_size && remaining > 1
              if previous_is_zero
                start = symbol
                symbol += 1 while symbol < alphabet_size &&
                    @distribution[symbol].zero?
                if symbol == alphabet_size
                  raise Omnizip::CompressionError, "bad FSE distribution"
                end

                while symbol >= start + 24
                  start += 24
                  bit_stream |= 0xFFFF << bit_count
                  out.push(bit_stream & 0xFF, (bit_stream >> 8) & 0xFF)
                  bit_stream >>= 16
                end
                while symbol >= start + 3
                  start += 3
                  bit_stream |= 3 << bit_count
                  bit_count += 2
                end
                bit_stream |= (symbol - start) << bit_count
                bit_count += 2
                if bit_count > 16
                  out.push(bit_stream & 0xFF, (bit_stream >> 8) & 0xFF)
                  bit_stream >>= 16
                  bit_count -= 16
                end
              end

              count = @distribution[symbol]
              symbol += 1
              max = ((2 * threshold) - 1) - remaining
              remaining -= count.negative? ? -count : count
              count_val = count + 1
              count_val += max if count_val >= threshold

              bit_stream |= count_val << bit_count
              bit_count += nb_bits
              bit_count -= 1 if count_val < max

              previous_is_zero = count_val == 1
              raise Omnizip::CompressionError, "FSE NCount remaining < 1" if remaining < 1

              while remaining < threshold
                nb_bits -= 1
                threshold >>= 1
              end

              if bit_count > 16
                out.push(bit_stream & 0xFF, (bit_stream >> 8) & 0xFF)
                bit_stream >>= 16
                bit_count -= 16
              end
            end

            unless remaining == 1
              raise Omnizip::CompressionError,
                    "FSE NCount remaining != 1 (#{remaining})"
            end

            if bit_count.positive?
              n_bytes = (bit_count + 7) / 8
              out.push(*Array.new(n_bytes) { |i| (bit_stream >> (8 * i)) & 0xFF })
            end

            out.pack("C*")
          end
          # rubocop:enable Metrics/MethodLength

          # Encode `symbols` into a 2-state interleaved reverse
          # bitstream (C FSE_compress_usingCTable).
          #
          # @param symbols [Array<Integer>]
          # @return [String] bitstream bytes ending with the 1-bit mark
          # Direct port of C FSE_compress_usingCTable.
          # rubocop:disable Metrics/AbcSize
          def compress_symbols(symbols)
            return "" if symbols.length <= 2

            bitc = BitCStream.new
            ip = symbols.length

            ip -= 1
            if symbols.length.odd?
              s1 = CState.init2(self, symbols[ip])
              ip -= 1
              s2 = CState.init2(self, symbols[ip])
              ip -= 1
              s1.encode(bitc, self, symbols[ip])
              bitc.flush
            else
              s2 = CState.init2(self, symbols[ip])
              ip -= 1
              s1 = CState.init2(self, symbols[ip])
            end
            # rubocop:enable Metrics/AbcSize

            while ip.positive?
              ip -= 1
              s2.encode(bitc, self, symbols[ip])
              break if ip.zero?

              ip -= 1
              s1.encode(bitc, self, symbols[ip])
              bitc.flush
            end

            s2.flush(bitc)
            s1.flush(bitc)
            bitc.close
          end

          # Serialize table description + bitstream for `symbols`.
          #
          # @return [String]
          def compress(symbols)
            write_ncount + compress_symbols(symbols)
          end

          # @return [Array<Integer>] state transition table
          attr_reader :state_table

          # @return [Array<SymbolTT>]
          attr_reader :symbol_tt

          private

          # Direct port of C FSE_buildCTable.
          # rubocop:disable Metrics/AbcSize
          def build_encoding_tables
            table_size = 1 << @table_log
            step = (table_size >> 1) + (table_size >> 3) + 3
            mask = table_size - 1
            max_sv1 = @max_symbol_value + 1

            table_symbol = Array.new(table_size, 0xFFFF)
            high_threshold = table_size - 1

            cumul = Array.new(max_sv1 + 1, 0)
            (1..max_sv1).each do |u|
              if @distribution[u - 1] == -1
                cumul[u] = cumul[u - 1] + 1
                table_symbol[high_threshold] = u - 1
                high_threshold -= 1
              else
                cumul[u] = cumul[u - 1] + @distribution[u - 1]
              end
              # rubocop:enable Metrics/AbcSize
            end
            cumul[max_sv1] = table_size + 1

            position = 0
            @distribution.each_with_index do |freq, symbol|
              next unless freq.positive?

              freq.times do
                table_symbol[position] = symbol
                position = (position + step) & mask
                position = (position + step) & mask while position > high_threshold
              end
            end

            @state_table = Array.new(table_size, 0)
            table_size.times do |u|
              s = table_symbol[u]
              @state_table[cumul[s]] = table_size + u
              cumul[s] += 1
            end

            @symbol_tt = Array.new(max_sv1) { SymbolTT.new(0, 0) }
            total = 0
            max_sv1.times do |s|
              case @distribution[s]
              when 0
                @symbol_tt[s].delta_nb_bits = ((@table_log + 1) << 16) -
                  (1 << @table_log)
              when -1, 1
                @symbol_tt[s].delta_nb_bits = (@table_log << 16) -
                  (1 << @table_log)
                @symbol_tt[s].delta_find_state = total - 1
                total += 1
              else
                n = @distribution[s]
                max_bits_out = @table_log - Constants.highbit32(n - 1)
                min_state_plus = n << max_bits_out
                @symbol_tt[s].delta_nb_bits = (max_bits_out << 16) - min_state_plus
                @symbol_tt[s].delta_find_state = total - n
                total += n
              end
            end
          end

          # Forward bit writer (C BIT_CStream): accumulates at the low
          # end and flushes whole bytes.
          class BitCStream
            def initialize
              @container = 0
              @bit_pos = 0
            end

            # @param value [Integer] bits in the low end
            # @param nb_bits [Integer] 0..31
            def add_bits(value, nb_bits)
              mask = (1 << nb_bits) - 1
              @container |= (value & mask) << @bit_pos
              @bit_pos += nb_bits
            end

            def flush
              nb_bytes = @bit_pos >> 3
              @bytes ||= []
              nb_bytes.times do |i|
                @bytes << ((@container >> (8 * i)) & 0xFF)
              end
              @container >>= nb_bytes * 8
              @bit_pos &= 7
            end

            # Add the 1 end-mark bit and flush everything.
            #
            # @return [String]
            def close
              add_bits(1, 1)
              flush
              @bytes << (@container & 0xFF) if @bit_pos.positive?
              @bytes.pack("C*")
            end
          end

          # FSE encoder state (value in [table_size, 2*table_size)).
          class CState
            attr_reader :value

            def initialize(value, state_log)
              @value = value
              @state_log = state_log
            end

            # Initialize to the baseline for the first symbol to encode
            # (the last to decode); C FSE_initCState2.
            # rubocop:disable-next Metrics/AbcSize
            def self.init2(table, symbol)
              s_tt = table.symbol_tt[symbol]
              nb_bits_out = (s_tt.delta_nb_bits + (1 << 15)) >> 16
              value = (nb_bits_out << 16) - s_tt.delta_nb_bits
              idx = (value >> nb_bits_out) + s_tt.delta_find_state
              new(table.state_table[idx], table.table_log)
            end

            def encode(bitc, table, symbol)
              s_tt = table.symbol_tt[symbol]
              nb_bits_out = (@value + s_tt.delta_nb_bits) >> 16
              bitc.add_bits(@value, nb_bits_out)
              idx = (@value >> nb_bits_out) + s_tt.delta_find_state
              @value = table.state_table[idx]
            end

            def flush(bitc)
              bitc.add_bits(@value, @state_log)
              bitc.flush
            end
          end
        end
      end
    end
  end
end
