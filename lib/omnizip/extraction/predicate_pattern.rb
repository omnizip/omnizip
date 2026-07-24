# frozen_string_literal: true

module Omnizip
  module Extraction
    # Implements custom predicate pattern matching for archive entries
    #
    # Allows using arbitrary Ruby blocks to determine if an entry matches.
    class PredicatePattern
      attr_reader :predicate, :description

      # Initialize a new predicate pattern
      #
      # @param description [String] Human-readable description
      # @param predicate [Proc] Block that tests entries
      # @yield [entry] Entry to test
      # @yieldreturn [Boolean] Whether entry matches
      def initialize(description = "custom predicate", &predicate)
        raise ArgumentError, "Block required" unless predicate

        @description = description
        @predicate = predicate
      end

      # Check if an entry matches the predicate
      #
      # @param entry [Object] Entry to check (can be filename or entry object)
      # @return [Boolean]
      def match?(entry)
        @predicate.call(entry)
      rescue StandardError => e
        # If predicate raises error, treat as non-match
        warn "Predicate error for #{entry}: #{e.message}"
        false
      end

      # Convert pattern to string
      #
      # @return [String]
      def to_s
        @description
      end

      # Call the predicate directly
      #
      # @param entry [Object] Entry to check
      # @return [Boolean]
      def call(entry)
        match?(entry)
      end
    end
  end
end
