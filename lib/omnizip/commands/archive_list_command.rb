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

require_relative "../cli/output_formatter"
require_relative "../formats/seven_zip/reader"
require_relative "../extraction"

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
        archive = if archive_file.end_with?(".zip")
                   Omnizip::Zip::File.open(archive_file)
                 elsif archive_file.end_with?(".rar")
                   Formats::Rar::Reader.new(archive_file).open
                 else
                   Formats::SevenZip::Reader.new(archive_file).open
                 end

        entries = if patterns || excludes
                   filter_entries(archive, patterns, excludes)
                 else
                   archive.respond_to?(:entries) ? archive.entries : archive.to_a
                 end

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

      def filter_entries(archive, patterns, excludes)
        filter = Extraction::FilterChain.new

        # Add include patterns
        if patterns
          patterns.each { |pattern| filter.include_pattern(pattern) }
        end

        # Add exclude patterns
        if excludes
          excludes.each { |pattern| filter.exclude_pattern(pattern) }
        end

        entries = archive.respond_to?(:entries) ? archive.entries : archive.to_a
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
            name
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
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB]
        size = bytes.to_f
        unit_idx = 0

        while size >= 1024 && unit_idx < units.length - 1
          size /= 1024.0
          unit_idx += 1
        end

        if size < 10
          format("%.2f %s", size, units[unit_idx])
        elsif size < 100
          format("%.1f %s", size, units[unit_idx])
        else
          format("%.0f %s", size, units[unit_idx])
        end
      end

      # Helper methods to handle different entry types
      def entry_name(entry)
        entry.respond_to?(:name) ? entry.name : entry.to_s
      end

      def entry_directory?(entry)
        entry.respond_to?(:directory?) && entry.directory?
      end

      def entry_size(entry)
        entry.respond_to?(:size) ? entry.size : 0
      end

      def entry_compressed_size(entry)
        entry.respond_to?(:compressed_size) ? entry.compressed_size : nil
      end

      def entry_has_stream?(entry)
        entry.respond_to?(:has_stream?) ? entry.has_stream? : true
      end

      def entry_mtime(entry)
        entry.respond_to?(:mtime) ? entry.mtime : nil
      end
    end
  end
end
