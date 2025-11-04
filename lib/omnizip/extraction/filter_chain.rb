# frozen_string_literal: true

require_relative "pattern_matcher"

module Omnizip
  module Extraction
    # Combines multiple pattern matchers with AND/OR logic
    #
    # Supports include and exclude patterns, allowing complex
    # filtering scenarios like "all .rb files except in test/".
    class FilterChain
      attr_reader :include_patterns, :exclude_patterns,
                  :include_predicates, :exclude_predicates

      # Initialize a new filter chain
      def initialize
        @include_patterns = []
        @exclude_patterns = []
        @include_predicates = []
        @exclude_predicates = []
      end

      # Add an include pattern
      #
      # @param pattern [String, Regexp, Proc] Pattern to include
      # @return [self]
      def include_pattern(pattern)
        @include_patterns << PatternMatcher.new(pattern)
        self
      end

      # Add an exclude pattern
      #
      # @param pattern [String, Regexp, Proc] Pattern to exclude
      # @return [self]
      def exclude_pattern(pattern)
        @exclude_patterns << PatternMatcher.new(pattern)
        self
      end

      # Add an include predicate
      #
      # @yield [entry] Entry to test
      # @yieldreturn [Boolean] Whether to include entry
      # @return [self]
      def include(&predicate)
        @include_predicates << predicate if predicate
        self
      end

      # Add an exclude predicate
      #
      # @yield [entry] Entry to test
      # @yieldreturn [Boolean] Whether to exclude entry
      # @return [self]
      def exclude(&predicate)
        @exclude_predicates << predicate if predicate
        self
      end

      # Check if an entry matches the filter chain
      #
      # Logic:
      # - If no includes, everything passes (except excludes)
      # - If includes exist, entry must match at least one include
      # - Entry must not match any exclude
      #
      # @param entry [Object] Entry to check (filename or entry object)
      # @param filename [String, nil] Explicit filename (if entry is object)
      # @return [Boolean]
      def match?(entry, filename: nil)
        name = filename || extract_filename(entry)

        # Check excludes first (faster to reject)
        return false if excluded?(entry, name)

        # Check includes
        included?(entry, name)
      end

      # Filter an array of entries
      #
      # @param entries [Array] Entries to filter
      # @return [Array] Matching entries
      def filter(entries)
        entries.select { |entry| match?(entry) }
      end

      # Check if chain has any conditions
      #
      # @return [Boolean]
      def any?
        !@include_patterns.empty? ||
          !@exclude_patterns.empty? ||
          !@include_predicates.empty? ||
          !@exclude_predicates.empty?
      end

      # Get count of all conditions
      #
      # @return [Integer]
      def count
        @include_patterns.size +
          @exclude_patterns.size +
          @include_predicates.size +
          @exclude_predicates.size
      end

      private

      # Check if entry is included
      #
      # @param entry [Object] Entry to check
      # @param filename [String] Filename
      # @return [Boolean]
      def included?(entry, filename)
        # If no include patterns/predicates, include by default
        has_includes = !@include_patterns.empty? ||
                       !@include_predicates.empty?
        return true unless has_includes

        # Check if matches any include pattern
        pattern_match = @include_patterns.any? do |matcher|
          matcher.match?(filename)
        end

        # Check if matches any include predicate
        predicate_match = @include_predicates.any? do |predicate|
          predicate.call(entry)
        end

        pattern_match || predicate_match
      end

      # Check if entry is excluded
      #
      # @param entry [Object] Entry to check
      # @param filename [String] Filename
      # @return [Boolean]
      def excluded?(entry, filename)
        # Check if matches any exclude pattern
        pattern_match = @exclude_patterns.any? do |matcher|
          matcher.match?(filename)
        end

        # Check if matches any exclude predicate
        predicate_match = @exclude_predicates.any? do |predicate|
          predicate.call(entry)
        end

        pattern_match || predicate_match
      end

      # Extract filename from entry object
      #
      # @param entry [Object] Entry object or string
      # @return [String]
      def extract_filename(entry)
        case entry
        when String
          entry
        else
          # Try common filename methods
          if entry.respond_to?(:name)
            entry.name
          elsif entry.respond_to?(:path)
            entry.path
          elsif entry.respond_to?(:filename)
            entry.filename
          else
            entry.to_s
          end
        end
      end
    end
  end
end
