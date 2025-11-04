# frozen_string_literal: true

require_relative "pattern_matcher"
require_relative "filter_chain"
require_relative "../models/match_result"

module Omnizip
  module Extraction
    # Coordinates selective extraction from archives
    #
    # Extracts only files matching specified patterns, efficiently
    # skipping non-matched files without decompression.
    class SelectiveExtractor
      attr_reader :archive, :filter

      # Initialize a new selective extractor
      #
      # @param archive [Object] Archive to extract from
      # @param filter [FilterChain, PatternMatcher, Object] Filter to apply
      def initialize(archive, filter = nil)
        @archive = archive
        @filter = normalize_filter(filter)
      end

      # Extract matching files to destination
      #
      # @param dest [String] Destination directory
      # @param options [Hash] Extraction options
      # @option options [Boolean] :preserve_paths Keep directory structure
      # @option options [Boolean] :flatten Extract all to root
      # @option options [Boolean] :overwrite Overwrite existing files
      # @option options [Progress::ProgressTracker] :progress Progress tracker
      # @return [Array<String>] Paths of extracted files
      def extract(dest, options = {})
        FileUtils.mkdir_p(dest)
        extracted = []

        entries_to_extract = list_matches
        total = entries_to_extract.size
        current = 0

        entries_to_extract.each do |entry|
          dest_path = build_dest_path(entry, dest, options)
          extract_entry(entry, dest_path, options)
          extracted << dest_path

          # Update progress if tracker provided
          current += 1
          update_progress(options[:progress], current, total, entry)
        end

        extracted
      end

      # Extract matching files to memory
      #
      # @return [Hash<String, String>] Hash of filename => content
      def extract_to_memory
        result = {}

        list_matches.each do |entry|
          filename = entry_filename(entry)
          content = read_entry_content(entry)
          result[filename] = content
        end

        result
      end

      # List matching entries without extracting
      #
      # @return [Array] Matching entries
      def list_matches
        return list_all if @filter.nil?

        list_all.grep(@filter)
      end

      # Count matching entries
      #
      # @return [Integer]
      def count_matches
        list_matches.size
      end

      # Get match result with statistics
      #
      # @return [Models::MatchResult]
      def match_result
        all_entries = list_all
        matches = if @filter
                    all_entries.grep(@filter)
                  else
                    all_entries
                  end

        Models::MatchResult.new(
          @filter&.to_s || "all",
          matches: matches,
          total_scanned: all_entries.size
        )
      end

      private

      # Normalize filter to FilterChain or PatternMatcher
      #
      # @param filter [Object] Input filter
      # @return [FilterChain, PatternMatcher, nil]
      def normalize_filter(filter)
        case filter
        when FilterChain, PatternMatcher
          filter
        when nil
          nil
        else
          PatternMatcher.new(filter)
        end
      end

      # List all entries in archive
      #
      # @return [Array] All entries
      def list_all
        if @archive.respond_to?(:entries)
          @archive.entries
        elsif @archive.respond_to?(:each)
          @archive.to_a
        else
          raise Error, "Archive does not support listing entries"
        end
      end

      # Extract a single entry
      #
      # @param entry [Object] Entry to extract
      # @param dest_path [String] Destination path
      # @param options [Hash] Options
      def extract_entry(entry, dest_path, options)
        return if File.exist?(dest_path) && !options[:overwrite]

        # Create parent directory
        FileUtils.mkdir_p(File.dirname(dest_path))

        # Extract content
        content = read_entry_content(entry)
        File.binwrite(dest_path, content)
      end

      # Read content from an entry
      #
      # @param entry [Object] Entry to read
      # @return [String] Entry content
      def read_entry_content(entry)
        if entry.respond_to?(:read)
          entry.read
        elsif entry.respond_to?(:get_input_stream)
          entry.get_input_stream.read
        elsif @archive.respond_to?(:read)
          @archive.read(entry)
        else
          raise Error, "Cannot read entry content"
        end
      end

      # Build destination path for an entry
      #
      # @param entry [Object] Entry
      # @param dest [String] Destination directory
      # @param options [Hash] Options
      # @return [String] Full destination path
      def build_dest_path(entry, dest, options)
        filename = entry_filename(entry)

        if options[:flatten]
          # Extract to root, use basename only
          File.join(dest, File.basename(filename))
        elsif options[:preserve_paths] != false
          # Preserve directory structure (default)
          File.join(dest, filename)
        else
          # Use basename
          File.join(dest, File.basename(filename))
        end
      end

      # Get filename from entry
      #
      # @param entry [Object] Entry
      # @return [String] Filename
      def entry_filename(entry)
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

      # Update progress tracker
      #
      # @param tracker [Progress::ProgressTracker, nil] Progress tracker
      # @param current [Integer] Current count
      # @param total [Integer] Total count
      # @param entry [Object] Current entry
      def update_progress(tracker, current, total, entry)
        return unless tracker

        tracker.update(
          current_bytes: current,
          total_bytes: total,
          current_file: entry_filename(entry)
        )
      end
    end
  end
end
