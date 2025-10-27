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

        list_archive(archive_file, verbose)
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

      def list_archive(archive_file, verbose)
        reader = Formats::SevenZip::Reader.new(archive_file).open

        puts "Archive: #{archive_file}"
        puts ""

        if verbose
          display_detailed_listing(reader)
        else
          display_simple_listing(reader)
        end

        puts ""
        summary_stats(reader)
      rescue StandardError => e
        raise Omnizip::CompressionError,
              "Failed to list archive: #{e.message}"
      end

      def display_simple_listing(reader)
        puts "Contents:"
        puts ""

        reader.entries.each do |entry|
          type_indicator = entry.directory? ? "D" : "F"
          puts "  [#{type_indicator}] #{entry.name}"
        end
      end

      def display_detailed_listing(reader)
        puts "Type       Size         Compressed   Modified             Name"
        puts "-" * 80

        reader.entries.each do |entry|
          type = entry.directory? ? "Dir" : "File"
          size = entry.directory? ? "-" : format_bytes(entry.size)
          compressed = if entry.directory? || !entry.has_stream?
                         "-"
                       else
                         format_bytes(entry.compressed_size || 0)
                       end
          mtime = if entry.mtime
                    entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
                  else
                    "-"
                  end

          puts format(
            "%-10s %-12s %-12s %-20s %s",
            type,
            size,
            compressed,
            mtime,
            entry.name
          )
        end
      end

      def summary_stats(reader)
        total_files = reader.entries.count { |e| !e.directory? }
        total_dirs = reader.entries.count(&:directory?)
        total_size = reader.entries.sum { |e| e.size || 0 }
        total_compressed = reader.entries.sum do |e|
          e.compressed_size || 0
        end

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
    end
  end
end
