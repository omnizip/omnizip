# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Represents the result of pattern matching against archive entries.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    # The serialized "matches" is the match COUNT (not the entry
    # objects, which are arbitrary caller types); the live entry
    # collection stays a plain reader.
    class MatchResult < Lutaml::Model::Serializable
      include Enumerable

      attribute :total_scanned, :integer, default: 0

      attribute :pattern_repr, :string, method: :pattern_to_s
      attribute :match_count, :integer, method: :count
      attribute :rate, :double, method: :match_rate

      key_value do
        map "pattern", to: :pattern_repr,
                       render_default: true, render_nil: true
        map "matches", to: :match_count,
                       render_default: true, render_nil: true
        map "scanned", to: :total_scanned,
                       render_default: true, render_nil: true
        map "match_rate", to: :rate,
                          render_default: true, render_nil: true
      end

      attr_reader :matches, :pattern

      # Initialize a new match result
      #
      # @param pattern [Object] The pattern that was matched
      # @param matches [Array] Array of matched entries
      # @param total_scanned [Integer] Total entries scanned
      def initialize(pattern = nil, matches: [], total_scanned: 0)
        super(total_scanned: total_scanned)
        @pattern = pattern
        @matches = Array(matches)
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
        self.total_scanned = total_scanned + count
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
        return 0.0 if total_scanned.zero?

        count.to_f / total_scanned
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

      # Serialized pattern representation.
      #
      # @return [String] The pattern as a string
      def pattern_to_s
        @pattern.to_s
      end
    end
  end
end
