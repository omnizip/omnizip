# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # Match candidate result from LZ77 match finding
      class Match
        attr_reader :distance, :length

        def initialize(distance, length)
          @distance = distance
          @length = length
        end

        # Check if match is valid for given dictionary size
        #
        # @param dict_size [Integer] Dictionary size in bytes
        # @return [Boolean] true if match is valid
        def valid?(dict_size)
          @distance <= dict_size && @length >= 2
        end

        # String representation for debugging
        #
        # @return [String] Match description
        def to_s
          "Match(dist=#{@distance}, len=#{@length})"
        end
      end
    end
  end
end
