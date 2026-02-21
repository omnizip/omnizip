# frozen_string_literal: true

module Omnizip
  # Provides selective extraction capabilities for archives
  #
  # Supports extracting files matching glob patterns, regex patterns,
  # or custom predicates without extracting the entire archive.
  module Extraction
    autoload :PatternMatcher, "omnizip/extraction/pattern_matcher"
    autoload :FilterChain, "omnizip/extraction/filter_chain"
    autoload :SelectiveExtractor, "omnizip/extraction/selective_extractor"
    autoload :GlobPattern, "omnizip/extraction/glob_pattern"
    autoload :RegexPattern, "omnizip/extraction/regex_pattern"
    autoload :PredicatePattern, "omnizip/extraction/predicate_pattern"
    class << self
      # Extract files matching a pattern from an archive
      #
      # @param archive [Object] Archive to extract from
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @param dest [String] Destination directory
      # @param options [Hash] Extraction options
      # @option options [Boolean] :preserve_paths Keep directory structure
      # @option options [Boolean] :flatten Extract all to destination root
      # @option options [Boolean] :overwrite Overwrite existing files
      # @return [Array<String>] Paths of extracted files
      def extract_matching(archive, pattern, dest, options = {})
        filter = build_filter(pattern)
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.extract(dest, options)
      end

      # Extract files matching a pattern to memory
      #
      # @param archive [Object] Archive to extract from
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Hash<String, String>] Hash of filename => content
      def extract_to_memory_matching(archive, pattern)
        filter = build_filter(pattern)
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.extract_to_memory
      end

      # List files matching a pattern without extracting
      #
      # @param archive [Object] Archive to list from
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Array] Matching entries
      def list_matching(archive, pattern)
        filter = build_filter(pattern)
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.list_matches
      end

      # Count files matching a pattern
      #
      # @param archive [Object] Archive to count in
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Integer] Number of matches
      def count_matching(archive, pattern)
        filter = build_filter(pattern)
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.count_matches
      end

      # Extract with a filter chain
      #
      # @param archive [Object] Archive to extract from
      # @param filter [FilterChain] Filter chain to apply
      # @param dest [String] Destination directory
      # @param options [Hash] Extraction options
      # @return [Array<String>] Paths of extracted files
      def extract_with_filter(archive, filter, dest, options = {})
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.extract(dest, options)
      end

      # Get match result with statistics
      #
      # @param archive [Object] Archive to analyze
      # @param pattern [String, Regexp, Array] Pattern(s) to match
      # @return [Models::MatchResult] Match result with statistics
      def match_result(archive, pattern)
        filter = build_filter(pattern)
        extractor = SelectiveExtractor.new(archive, filter)
        extractor.match_result
      end

      private

      # Build filter from pattern(s)
      #
      # @param pattern [Object] Pattern or array of patterns
      # @return [PatternMatcher, FilterChain]
      def build_filter(pattern)
        case pattern
        when Array
          # Multiple patterns - combine with OR logic
          filter = FilterChain.new
          pattern.each { |p| filter.include_pattern(p) }
          filter
        when FilterChain
          pattern
        else
          # Single pattern
          PatternMatcher.new(pattern)
        end
      end
    end
  end
end
