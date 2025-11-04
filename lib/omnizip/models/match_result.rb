# frozen_string_literal: true

module Omnizip
  module Models
    # Represents the result of pattern matching against archive entries
    #
    # Contains matched entries with metadata about the matching process.
    class MatchResult
      attr_reader :matches, :total_scanned, :pattern

      # Initialize a new match result
      #
      # @param pattern [Object] The pattern that was matched
      # @param matches [Array] Array of matched entries
      # @param total_scanned [Integer] Total entries scanned
      def initialize(pattern, matches: [], total_scanned: 0)
        @pattern = pattern
        @matches = Array(matches)
        @total_scanned = total_scanned
      end

      # Add a matched entry
      #
      # @param entry [Object] Entry that matched
      # @return [self]
      def add_match(entry)
        @matches << entry
        self
      end

      # Increment the scan counter
      #
      # @param count [Integer] Number to increment by
      # @return [self]
      def increment_scanned(count = 1)
        @total_scanned += count
        self
      end

      # Get the number of matches
      #
      # @return [Integer]
      def count
        @matches.size
      end

      # Check if any matches were found
      #
      # @return [Boolean]
      def any?
        !@matches.empty?
      end

      # Check if no matches were found
      #
      # @return [Boolean]
      def none?
        @matches.empty?
      end

      # Get match rate (matches/scanned)
      #
      # @return [Float] Match rate between 0.0 and 1.0
      def match_rate
        return 0.0 if @total_scanned.zero?

        count.to_f / @total_scanned
      end

      # Get match percentage
      #
      # @return [Float] Match percentage between 0.0 and 100.0
      def match_percentage
        match_rate * 100.0
      end

      # Iterate over matches
      #
      # @yield [entry] Each matched entry
      # @return [Enumerator, self]
      def each(&block)
        return matches.to_enum unless block

        matches.each(&block)
        self
      end

      # Get first match
      #
      # @return [Object, nil]
      def first
        @matches.first
      end

      # Get last match
      #
      # @return [Object, nil]
      def last
        @matches.last
      end

      # Convert to array
      #
      # @return [Array]
      def to_a
        @matches.dup
      end

      # Get summary hash
      #
      # @return [Hash]
      def to_h
        {
          pattern: @pattern.to_s,
          matches: count,
          scanned: @total_scanned,
          match_rate: match_rate
        }
      end
    end
  end
end
