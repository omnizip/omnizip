# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

module Omnizip
  module Commands
    # Command to list contents of .7z archives.
    class ArchiveListCommand
      attr_reader :options

      # Initialize archive list command with options.
      #
      # @param options [Hash] Command options from Thor
      def initialize(options = {})
        @options = options
      end

      # Execute the archive list command.
      #
      # @param archive_file [String] Path to .7z archive
      # @return [void]
      def run(archive_file)
        validate_input(archive_file)

        verbose = options[:verbose] || false
        patterns = Array(options[:pattern]) if options[:pattern]
        excludes = Array(options[:exclude]) if options[:exclude]
        count_only = options[:count] || false

        list_archive(archive_file, verbose, patterns, excludes, count_only)
      end

      private

      def validate_input(archive_file)
        unless File.exist?(archive_file)
          raise Omnizip::IOError, "Archive not found: #{archive_file}"
        end

        return if File.readable?(archive_file)

        raise Omnizip::IOError,
              "Archive not readable: #{archive_file}"
      end

      def list_archive(archive_file, verbose, patterns, excludes, count_only)
        # Route through the handler seam: every format's reader is
        # chosen by the extension routes, not by hand-rolled branches
        entries = Omnizip.list_archive(archive_file, details: true)
          .map { |h| EntryAdapter.new(h) }

        entries = filter_entries(entries, patterns, excludes) if patterns || excludes

        if count_only
          puts "Matches: #{entries.size}"
          return
        end

        puts "Archive: #{archive_file}"
        puts ""

        if verbose
          display_detailed_listing_filtered(entries)
        else
          display_simple_listing_filtered(entries)
        end

        puts ""
        summary_stats_filtered(entries)
      rescue StandardError => e
        raise Omnizip::CompressionError,
              "Failed to list archive: #{e.message}"
      end

      def filter_entries(entries, patterns, excludes)
        filter = Extraction::FilterChain.new

        # Add include patterns
        patterns&.each { |pattern| filter.include_pattern(pattern) }

        # Add exclude patterns
        excludes&.each { |pattern| filter.exclude_pattern(pattern) }

        filter.filter(entries)
      end

      def display_simple_listing_filtered(entries)
        puts "Contents:"
        puts ""

        entries.each do |entry|
          type_indicator = entry_directory?(entry) ? "D" : "F"
          name = entry_name(entry)
          puts "  [#{type_indicator}] #{name}"
        end
      end

      def display_detailed_listing_filtered(entries)
        puts "Type       Size         Compressed   Modified             Name"
        puts "-" * 80

        entries.each do |entry|
          type = entry_directory?(entry) ? "Dir" : "File"
          size = entry_directory?(entry) ? "-" : format_bytes(entry_size(entry))
          compressed = if entry_directory?(entry) || !entry_has_stream?(entry)
                         "-"
                       else
                         format_bytes(entry_compressed_size(entry) || 0)
                       end
          mtime = if entry_mtime(entry)
                    entry_mtime(entry).strftime("%Y-%m-%d %H:%M:%S")
                  else
                    "-"
                  end
          name = entry_name(entry)

          puts format(
            "%-10s %-12s %-12s %-20s %s",
            type,
            size,
            compressed,
            mtime,
            name,
          )
        end
      end

      def summary_stats_filtered(entries)
        total_files = entries.count { |e| !entry_directory?(e) }
        total_dirs = entries.count { |e| entry_directory?(e) }
        total_size = entries.sum { |e| entry_size(e) || 0 }
        total_compressed = entries.sum { |e| entry_compressed_size(e) || 0 }

        puts "Summary:"
        puts "  Files: #{total_files}"
        puts "  Directories: #{total_dirs}"
        puts "  Total size: #{format_bytes(total_size)}"
        return unless total_compressed.positive? && total_size.positive?

        ratio = (1.0 - (total_compressed.to_f / total_size)) * 100
        puts "  Compressed size: #{format_bytes(total_compressed)}"
        puts "  Compression ratio: #{ratio.round(1)}%"
      end

      def format_bytes(bytes)
        Omnizip::CliOutputFormatter.format_size(bytes)
      end

      # Helper methods to handle different entry types. Each delegates
      # to the Omnizip::Entry contract; format-specific accessors stay
      # on the format entry classes themselves.
      def entry_name(entry)
        entry.entry_name || entry.to_s
      end

      def entry_directory?(entry)
        entry.entry_directory?
      end

      def entry_size(entry)
        entry.entry_size || 0
      end

      def entry_compressed_size(entry)
        entry.compressed_size
      end

      def entry_has_stream?(entry)
        entry.has_stream?
      end

      def entry_mtime(entry)
        entry.entry_mtime
      end

      # Presents handler list-detail hashes under the Omnizip::Entry
      # contract the display helpers already use
      # :fields, not :hash — Struct members must not override
      # Struct#hash
      EntryAdapter = Struct.new(:fields) do
        def entry_name = fields[:name]
        def entry_directory? = fields[:directory]
        def entry_size = fields[:size]
        def entry_mtime = fields[:mtime] || fields[:time]
        def compressed_size = fields[:compressed_size]
        def has_stream? = !fields[:directory] && fields[:size].to_i.positive?
      end
    end
  end
end
