# frozen_string_literal: true

module Omnizip
  module Extraction
    # Implements regex pattern matching for file paths
    #
    # Wraps Ruby Regexp objects to provide consistent interface
    # with other pattern types.
    class RegexPattern
      attr_reader :pattern

      # Initialize a new regex pattern
      #
      # @param pattern [Regexp, String] Regex pattern
      def initialize(pattern)
        @pattern = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
      end

      # Check if a filename matches the pattern
      #
      # @param filename [String] Filename to check
      # @return [Boolean]
      def match?(filename)
        @pattern.match?(filename.to_s)
      end

      # Get match data for a filename
      #
      # @param filename [String] Filename to check
      # @return [MatchData, nil]
      def match(filename)
        @pattern.match(filename.to_s)
      end

      # Convert pattern to string
      #
      # @return [String]
      def to_s
        @pattern.source
      end

      # Get the underlying regex
      #
      # @return [Regexp]
      def to_regexp
        @pattern
      end
    end
  end
end
