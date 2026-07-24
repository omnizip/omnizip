# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Compression
        module LZ77Huffman
          # LZ77 Match Finder for RAR compression
          class MatchFinder
            MAX_MATCH_LENGTH = 257
            MIN_MATCH_LENGTH = 3
            WINDOW_SIZE = 32768
            MAX_CHAIN_LENGTH = 1024

            class Match
              attr_reader :offset, :length

              def initialize(offset, length)
                @offset = offset
                @length = length
              end

              def ==(other)
                offset == other.offset && length == other.length
              end
            end

            attr_reader :window_size, :max_match_length

            def initialize(window_size = WINDOW_SIZE,
max_match_length = MAX_MATCH_LENGTH)
              @window_size = window_size
              @max_match_length = [max_match_length, MAX_MATCH_LENGTH].min
              @hash_table = {}
            end

            def find_match(data, position)
              return nil if position >= data.size
              return nil if data.size - position < MIN_MATCH_LENGTH

              # Index all positions up to current if not done yet
              ensure_indexed(data, position)

              hash_val = hash_bytes(data, position)
              candidates = @hash_table[hash_val] || []
              best_match = find_best_among_candidates(data, position,
                                                      candidates)
              update_hash(hash_val, position)
              best_match
            end

            def update(data, position)
              return if position >= data.size

              hash_val = hash_bytes(data, position)
              update_hash(hash_val, position)
            end

            def reset
              @hash_table.clear
              @last_indexed = -1
            end

            def hash_chain_count
              @hash_table.size
            end

            private

            def ensure_indexed(data, position)
              @last_indexed ||= -1
              start_pos = [@last_indexed + 1, 0].max
              (start_pos...position).each do |pos|
                next if pos + MIN_MATCH_LENGTH > data.size

                hash_val = hash_bytes(data, pos)
                @hash_table[hash_val] ||= []
                @hash_table[hash_val] << pos
              end
              @last_indexed = position - 1
            end

            def hash_bytes(data, position)
              return 0 if position + 2 >= data.size

              bytes = data.is_a?(String) ? data.bytes : data
              (bytes[position] << 16) ^ (bytes[position + 1] << 8) ^ bytes[position + 2]
            end

            def find_best_among_candidates(data, position, candidates)
              best_length = MIN_MATCH_LENGTH - 1
              best_offset = 0
              checked = 0

              candidates.reverse_each do |candidate_pos|
                offset = position - candidate_pos
                break if offset > @window_size

                checked += 1
                break if checked > MAX_CHAIN_LENGTH

                length = match_length(data, position, candidate_pos)
                if length > best_length
                  best_length = length
                  best_offset = offset
                  break if best_length >= @max_match_length
                end
              end

              return nil if best_length < MIN_MATCH_LENGTH

              Match.new(best_offset, best_length)
            end

            def match_length(data, pos1, pos2)
              bytes = data.is_a?(String) ? data.bytes : data
              max_len = [data.size - pos1, @max_match_length].min
              length = 0
              while length < max_len && bytes[pos1 + length] == bytes[pos2 + length]
                length += 1
              end
              length
            end

            def update_hash(hash_val, position)
              @hash_table[hash_val] ||= []
              @hash_table[hash_val] << position
              @hash_table[hash_val].shift if @hash_table[hash_val].size > MAX_CHAIN_LENGTH
            end
          end
        end
      end
    end
  end
end
