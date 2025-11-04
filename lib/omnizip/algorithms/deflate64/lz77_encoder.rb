# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Algorithms
    class Deflate64
      # LZ77 encoder with 64KB sliding window for Deflate64
      class LZ77Encoder
        include Constants

        attr_reader :window_size

        def initialize(window_size = DICTIONARY_SIZE)
          @window_size = window_size
          @window = []
          @hash_table = {}
          @position = 0
        end

        # Find matches in data and return array of literals and match tokens
        #
        # @param data [String] Input data to compress
        # @return [Array<Hash>] Array of match tokens
        def find_matches(data)
          tokens = []
          pos = 0

          while pos < data.bytesize
            match = find_longest_match(pos, data)

            if match && match[:length] >= MIN_MATCH_LENGTH
              tokens << {
                type: :match,
                length: match[:length],
                distance: match[:distance]
              }
              pos += match[:length]
            else
              tokens << {
                type: :literal,
                value: data.getbyte(pos)
              }
              pos += 1
            end

            update_window(data, pos)
          end

          tokens
        end

        private

        # Find longest match for current position
        #
        # @param pos [Integer] Current position in data
        # @param data [String] Input data
        # @return [Hash, nil] Match information or nil
        def find_longest_match(pos, data)
          return nil if pos + MIN_MATCH_LENGTH > data.bytesize

          best_match = nil
          best_length = MIN_MATCH_LENGTH - 1

          # Calculate hash for current position
          hash = calculate_hash(data, pos)
          candidates = @hash_table[hash] || []

          # Search through candidate matches
          candidates.reverse.take(MAX_CHAIN_LENGTH).each do |candidate_pos|
            distance = pos - candidate_pos
            break if distance > MAX_DISTANCE

            # Find match length
            length = match_length(data, pos, candidate_pos)

            if length > best_length
              best_length = length
              best_match = {
                length: length,
                distance: distance
              }

              break if length >= NICE_MATCH
            end
          end

          # Add current position to hash table
          @hash_table[hash] ||= []
          @hash_table[hash] << pos

          best_match
        end

        # Calculate match length between two positions
        #
        # @param data [String] Input data
        # @param pos1 [Integer] First position
        # @param pos2 [Integer] Second position
        # @return [Integer] Match length
        def match_length(data, pos1, pos2)
          max_length = [MAX_MATCH_LENGTH, data.bytesize - pos1].min
          length = 0

          while length < max_length &&
                data.getbyte(pos1 + length) == data.getbyte(pos2 + length)
            length += 1
          end

          length
        end

        # Calculate hash value for position
        #
        # @param data [String] Input data
        # @param pos [Integer] Position to hash
        # @return [Integer] Hash value
        def calculate_hash(data, pos)
          return 0 if pos + MIN_MATCH_LENGTH > data.bytesize

          hash = 0
          MIN_MATCH_LENGTH.times do |i|
            hash = ((hash << HASH_SHIFT) ^
              data.getbyte(pos + i)) & (HASH_SIZE - 1)
          end
          hash
        end

        # Update sliding window
        #
        # @param data [String] Input data
        # @param pos [Integer] Current position
        def update_window(data, pos)
          @window << data.getbyte(pos - 1) if pos > 0
          @window.shift if @window.size > @window_size
          @position = pos
        end
      end
    end
  end
end