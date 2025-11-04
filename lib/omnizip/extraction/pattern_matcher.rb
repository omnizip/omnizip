# frozen_string_literal: true

require_relative "glob_pattern"
require_relative "regex_pattern"
require_relative "predicate_pattern"

module Omnizip
  module Extraction
    # Coordinates pattern matching across different pattern types
    #
    # Automatically detects pattern type and delegates to appropriate
    # pattern implementation (glob, regex, or predicate).
    class PatternMatcher
      # Initialize a new pattern matcher
      #
      # @param pattern [String, Regexp, Proc, Object] Pattern to match
      def initialize(pattern)
        @pattern = build_pattern(pattern)
      end

      # Check if a filename matches the pattern
      #
      # @param filename [String] Filename to check
      # @return [Boolean]
      def match?(filename)
        @pattern.match?(filename)
      end

      # Match against multiple filenames
      #
      # @param filenames [Array<String>] Filenames to check
      # @return [Array<String>] Matching filenames
      def match_all(filenames)
        filenames.select { |filename| match?(filename) }
      end

      # Get the underlying pattern object
      #
      # @return [GlobPattern, RegexPattern, PredicatePattern]
      attr_reader :pattern

      # Convert pattern to string
      #
      # @return [String]
      def to_s
        @pattern.to_s
      end

      private

      # Build appropriate pattern object from input
      #
      # @param pattern [Object] Input pattern
      # @return [GlobPattern, RegexPattern, PredicatePattern]
      def build_pattern(pattern)
        case pattern
        when Regexp
          RegexPattern.new(pattern)
        when Proc
          PredicatePattern.new("custom predicate", &pattern)
        when GlobPattern, RegexPattern, PredicatePattern
          pattern
        else
          # Assume string glob pattern
          GlobPattern.new(pattern.to_s)
        end
      end
    end
  end
end
