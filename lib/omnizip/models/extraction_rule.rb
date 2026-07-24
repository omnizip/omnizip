# frozen_string_literal: true

module Omnizip
  module Models
    # Represents a rule for extracting files from an archive
    #
    # Defines what files to extract and how to extract them using
    # patterns, predicates, and options.
    class ExtractionRule
      attr_reader :patterns, :predicates, :options

      # Initialize a new extraction rule
      #
      # @param patterns [Array<String, Regexp>] Patterns to match
      # @param predicates [Array<Proc>] Custom predicates for matching
      # @param options [Hash] Extraction options
      # @option options [Boolean] :preserve_paths Keep directory structure
      # @option options [Boolean] :flatten Extract all to destination root
      # @option options [Boolean] :overwrite Overwrite existing files
      # @option options [String] :dest_prefix Prefix for destination paths
      def initialize(patterns: [], predicates: [], options: {})
        @patterns = Array(patterns)
        @predicates = Array(predicates)
        @options = default_options.merge(options)
      end

      # Add a pattern to the rule
      #
      # @param pattern [String, Regexp] Pattern to add
      # @return [self]
      def add_pattern(pattern)
        @patterns << pattern
        self
      end

      # Add a predicate to the rule
      #
      # @param predicate [Proc] Predicate block to add
      # @return [self]
      def add_predicate(&predicate)
        @predicates << predicate if predicate
        self
      end

      # Check if any patterns are defined
      #
      # @return [Boolean]
      def patterns?
        !@patterns.empty?
      end

      # Check if any predicates are defined
      #
      # @return [Boolean]
      def predicates?
        !@predicates.empty?
      end

      # Check if the rule has any conditions
      #
      # @return [Boolean]
      def conditions?
        patterns? || predicates?
      end

      # Get option value
      #
      # @param key [Symbol] Option key
      # @return [Object] Option value
      def [](key)
        @options[key]
      end

      # Set option value
      #
      # @param key [Symbol] Option key
      # @param value [Object] Option value
      def []=(key, value)
        @options[key] = value
      end

      # Check if paths should be preserved
      #
      # @return [Boolean]
      def preserve_paths?
        @options[:preserve_paths]
      end

      # Check if paths should be flattened
      #
      # @return [Boolean]
      def flatten?
        @options[:flatten]
      end

      # Check if existing files should be overwritten
      #
      # @return [Boolean]
      def overwrite?
        @options[:overwrite]
      end

      private

      def default_options
        {
          preserve_paths: true,
          flatten: false,
          overwrite: false,
          dest_prefix: nil,
        }
      end
    end
  end
end
