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
    class LZMA < Algorithm
      # Configuration model for Match Finder behavior
      #
      # This model separates configuration from implementation, allowing
      # different match finding strategies (SDK-compatible vs simplified)
      # to be configured declaratively.
      #
      # @example SDK-compatible configuration
      #   config = MatchFinderConfig.new(
      #     mode: :sdk,
      #     hash_size: 65536,
      #     chain_length: 32,
      #     lazy_matching: false
      #   )
      #
      # @example Simplified configuration
      #   config = MatchFinderConfig.new(
      #     mode: :simplified,
      #     hash_size: 65536,
      #     chain_length: 1024
      #   )
      class MatchFinderConfig
        attr_accessor :mode, :hash_size, :chain_length, :search_mode,
                      :lazy_matching, :max_match_length, :window_size

        def initialize(mode: "simplified", hash_size: 65_536,
                       chain_length: 1024, search_mode: "hash_chain",
                       lazy_matching: false, max_match_length: 273,
                       window_size: 65_536)
          @mode = mode
          @hash_size = hash_size
          @chain_length = chain_length
          @search_mode = search_mode
          @lazy_matching = lazy_matching
          @max_match_length = max_match_length
          @window_size = window_size
        end

        # Validate configuration
        #
        # @return [Boolean] true if valid
        # @raise [ArgumentError] if configuration is invalid
        def validate!
          unless %w[sdk simplified].include?(mode)
            raise ArgumentError, "mode must be :sdk or :simplified"
          end

          unless %w[hash_chain binary_tree].include?(search_mode)
            raise ArgumentError,
                  "search_mode must be :hash_chain or :binary_tree"
          end

          raise ArgumentError, "hash_size must be positive" if hash_size <= 0

          if chain_length <= 0
            raise ArgumentError,
                  "chain_length must be positive"
          end
          if max_match_length < 2
            raise ArgumentError,
                  "max_match_length must be >= 2"
          end
          if window_size <= 0
            raise ArgumentError,
                  "window_size must be positive"
          end

          true
        end

        # Create SDK-compatible configuration
        #
        # @param dict_size [Integer] Dictionary size
        # @param level [Integer] Compression level (0-9)
        # @return [MatchFinderConfig] SDK-compatible configuration
        def self.sdk_config(dict_size: 65536, level: 5)
          # SDK uses different parameters based on dictionary size and level
          hash_size = dict_size >= (1 << 20) ? (1 << 20) : (1 << 16)

          # SDK nice_len varies by compression level:
          # Level 0-4: 32, Level 5-6: 64, Level 7-8: 128, Level 9: 273
          chain_length = case level
                         when 0..4 then 32
                         when 5..6 then 64
                         when 7..8 then 128
                         else 273
                         end

          new(
            mode: "sdk",
            hash_size: hash_size,
            chain_length: chain_length,
            search_mode: "hash_chain",
            lazy_matching: level >= 7, # Enable lazy matching for high compression
            max_match_length: 273,
            window_size: dict_size,
          )
        end

        # Create simplified configuration (backward compatible)
        #
        # @param dict_size [Integer] Dictionary size
        # @return [MatchFinderConfig] Simplified configuration
        def self.simplified_config(dict_size: 65536)
          new(
            mode: "simplified",
            hash_size: 65536,
            chain_length: 1024,
            search_mode: "hash_chain",
            lazy_matching: false,
            max_match_length: 273,
            window_size: dict_size,
          )
        end
      end
    end
  end
end
