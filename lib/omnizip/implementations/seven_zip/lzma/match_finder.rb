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

require_relative "../../../algorithms/lzma/constants"
require_relative "../../../algorithms/lzma/match_finder_config"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA
        # 7-Zip LZMA SDK match finder implementation.
        #
        # This is the original SdkMatchFinder moved from algorithms/lzma/sdk_match_finder.rb
        # to the new namespace structure.
        #
        # Ported from 7-Zip LZMA SDK by Igor Pavlov.
        class MatchFinder
          include Omnizip::Algorithms::LZMA::Constants

          # Represents a match found in the dictionary
          class Match
            attr_reader :length, :distance

            def initialize(length, distance)
              @length = length
              @distance = distance
            end
          end

          attr_reader :config

          # Initialize the SDK-compatible match finder
          #
          # @param config [MatchFinderConfig] Configuration object
          def initialize(config)
            @config = config
            @window_size = config.window_size
            @max_match_length = config.max_match_length
            @chain_length = config.chain_length
            @lazy_matching = config.lazy_matching

            # Hash table: maps hash value to position
            # SDK uses separate hash2 and hash3 tables, but we simplify
            # to single hash table with chaining
            @hash_table = {}

            # Hash chain: stores previous positions for each hash value
            @hash_chain = {}

            # CRC table for hash computation (SDK uses CRC)
            init_crc_table
          end

          # Find the longest match at the given position
          #
          # Implements SDK's GetMatches() function from LzFind.c
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos [Integer] Current position in data
          # @return [Match, nil] Best match or nil if no match found
          def find_longest_match(data, pos)
            return nil if pos >= data.size
            return nil if data.size - pos < MATCH_LEN_MIN

            if @lazy_matching && @lazy_match
              # Return lazy match from previous position
              match = @lazy_match
              @lazy_match = nil
              # Don't update hash - current position was already added when lazy match was created
              return match
            end

            best_match = find_best_match(data, pos)

            if @lazy_matching && best_match && pos + 1 < data.size
              # Try next position for potentially better match
              next_match = find_best_match(data, pos + 1)
              if next_match && next_match.length > best_match.length
                # Save better match for next call
                @lazy_match = next_match
                # Don't update hash - we'll add it when lazy match is consumed
                return nil
              end
            end

            # CRITICAL: Update hash AFTER finding matches
            # This ensures the current position is available for future matches
            update_hash(data, pos)
            best_match
          end

          # Reset the match finder state
          #
          # @return [void]
          def reset
            @hash_table.clear
            @hash_chain.clear
            @lazy_match = nil
          end

          private

          # Find best match at position (SDK's GetMatches core logic)
          #
          # Searches both 2-byte and 3-byte hash chains for the best match.
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos [Integer] Current position
          # @return [Match, nil] Best match or nil
          def find_best_match(data, pos)
            best_match = nil
            best_length = MATCH_LEN_MIN - 1

            hashes = compute_hashes(data, pos)
            return nil if hashes.empty?

            # Search both hash chains
            hashes.each_value do |hash_val|
              positions = @hash_chain[hash_val] || []
              next if positions.empty?

              # SDK traverses hash chain from most recent to oldest
              # Limited by chain_length (nice_len in SDK)
              count = 0
              positions.reverse_each do |prev_pos|
                break if count >= @chain_length
                break if pos <= prev_pos || pos - prev_pos > @window_size

                match_len = calculate_match_length(data, pos, prev_pos)

                if match_len > best_length
                  best_length = match_len
                  best_match = Match.new(match_len, pos - prev_pos)

                  # SDK optimization: stop if we found max length
                  break if best_length >= @max_match_length
                end

                count += 1
              end

              # If we found a full-length match, no need to check other hashes
              break if best_length >= @max_match_length
            end

            best_match
          end

          # Compute hash value using SDK's algorithm
          #
          # SDK uses CRC-based hashing with multiple hash levels:
          # - hash2: 2-byte hash
          # - hash3: 3-byte hash
          # - hash4: 4-byte hash (binary tree mode)
          #
          # We compute both 2-byte and 3-byte hashes and store matches
          # in both hash tables to ensure matches are found regardless
          # of which hash size is used at query time.
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos [Integer] Position to hash from
          # @return [Integer] Hash value (3-byte if available, else 2-byte)
          def compute_hash(data, pos)
            bytes = data.is_a?(String) ? data.bytes : data

            if pos + 3 <= data.size
              # 3-byte hash: CRC[byte[0]] ^ byte[1] ^ (byte[2] << 8)
              hash = @crc_table[bytes[pos]] ^ bytes[pos + 1]
              hash ^= (bytes[pos + 2] << 8)
              hash & 0xFFFF
            elsif pos + 2 <= data.size
              # 2-byte hash: CRC[byte[0]] ^ byte[1]
              hash = @crc_table[bytes[pos]] ^ bytes[pos + 1]
              hash & 0xFFFF
            end
            # Less than 2 bytes remaining returns nil implicitly
          end

          # Compute both 2-byte and 3-byte hashes
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos [Integer] Position to hash from
          # @return [Array<Integer>] Array of [hash2, hash3] or [hash2, nil]
          def compute_hashes(data, pos)
            bytes = data.is_a?(String) ? data.bytes : data
            hashes = {}

            # 2-byte hash (always compute if possible)
            if pos + 2 <= data.size
              hash2 = @crc_table[bytes[pos]] ^ bytes[pos + 1]
              hashes[:hash2] = hash2 & 0xFFFF
            end

            # 3-byte hash (only if 3+ bytes available)
            if pos + 3 <= data.size
              hash3 = @crc_table[bytes[pos]] ^ bytes[pos + 1]
              hash3 ^= (bytes[pos + 2] << 8)
              hashes[:hash3] = hash3 & 0xFFFF
            end

            hashes
          end

          # Calculate match length between two positions
          #
          # SDK compares bytes until mismatch or max length
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos1 [Integer] First position
          # @param pos2 [Integer] Second position
          # @return [Integer] Length of match
          def calculate_match_length(data, pos1, pos2)
            bytes = data.is_a?(String) ? data.bytes : data
            max_len = [data.size - pos1, @max_match_length].min
            length = 0

            while length < max_len && bytes[pos1 + length] == bytes[pos2 + length]
              length += 1
            end

            length
          end

          # Update hash table with new position
          #
          # Stores position in both 2-byte and 3-byte hash chains
          # to ensure matches are found regardless of hash size used at query time.
          #
          # @param data [String, Array<Integer>] Input data
          # @param pos [Integer] Position to add
          # @return [void]
          def update_hash(data, pos)
            hashes = compute_hashes(data, pos)
            return if hashes.empty?

            hashes.each_value do |hash_val|
              @hash_chain[hash_val] ||= []
              @hash_chain[hash_val] << pos

              # Keep hash chains from growing too large
              # SDK uses cyclic buffer, we use simple truncation
              max_chain = @chain_length * 2
              @hash_chain[hash_val].shift if @hash_chain[hash_val].size > max_chain
            end
          end

          # Initialize CRC table for hash computation
          #
          # SDK uses CRC32 table for hashing
          #
          # @return [void]
          def init_crc_table
            @crc_table = Array.new(256) do |i|
              crc = i
              8.times do
                if crc.anybits?(1)
                  crc = (crc >> 1) ^ 0xEDB88320
                else
                  crc >>= 1
                end
              end
              crc & 0xFF
            end
          end
        end
      end
    end
  end
end
