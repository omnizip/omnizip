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

require_relative "match_finder_config"
require_relative "match_finder"
require_relative "../../implementations/seven_zip/lzma/match_finder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Factory for creating Match Finder instances
      #
      # This factory implements the Factory pattern to create different
      # match finder implementations based on configuration. It provides
      # a clean separation between the configuration (what) and the
      # implementation (how).
      #
      # @example Creating an SDK-compatible match finder
      #   config = MatchFinderConfig.sdk_config(dict_size: 65536, level: 5)
      #   finder = MatchFinderFactory.create(config)
      #
      # @example Creating a simplified match finder
      #   config = MatchFinderConfig.simplified_config(dict_size: 65536)
      #   finder = MatchFinderFactory.create(config)
      class MatchFinderFactory
        # Create a match finder instance based on configuration
        #
        # @param config [MatchFinderConfig] Configuration object
        # @return [MatchFinder, Implementations::SevenZip::LZMA::MatchFinder] Match finder instance
        # @raise [ArgumentError] if configuration is invalid
        def self.create(config)
          config.validate!

          case config.mode
          when "sdk"
            Implementations::SevenZip::LZMA::MatchFinder.new(config)
          when "simplified"
            # Use original MatchFinder for backward compatibility
            MatchFinder.new(config.window_size, config.max_match_length)
          else
            raise ArgumentError, "Unknown match finder mode: #{config.mode}"
          end
        end

        # Create match finder from options hash (convenience method)
        #
        # @param options [Hash] Options hash
        # @option options [Boolean] :sdk_compatible Use SDK mode
        # @option options [Integer] :dict_size Dictionary size
        # @option options [Integer] :level Compression level
        # @return [MatchFinder, Implementations::SevenZip::LZMA::MatchFinder] Match finder instance
        def self.from_options(options = {})
          config = if options[:sdk_compatible]
                     MatchFinderConfig.sdk_config(
                       dict_size: options[:dict_size] || 65536,
                       level: options[:level] || 5,
                     )
                   else
                     MatchFinderConfig.simplified_config(
                       dict_size: options[:dict_size] || 65536,
                     )
                   end

          create(config)
        end
      end
    end
  end
end
