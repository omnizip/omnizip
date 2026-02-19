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
    # Command to extract .7z archives to a directory.
    class ArchiveExtractCommand
      attr_reader :options

      # Initialize archive extract command with options.
      #
      # @param options [Hash] Command options from Thor
      def initialize(options = {})
        @options = options
      end

      # Execute the archive extract command.
      #
      # @param archive_file [String] Path to .7z archive
      # @param output_dir [String] Directory to extract to
      # @return [void]
      def run(archive_file, output_dir = nil)
        validate_input(archive_file)

        # Default to current directory if not specified
        output_dir ||= "."
        output_dir = File.expand_path(output_dir)

        verbose = options[:verbose] || false
        patterns = Array(options[:pattern]) if options[:pattern]
        excludes = Array(options[:exclude]) if options[:exclude]
        regex = options[:regex]

        if verbose
          CliOutputFormatter.verbose_puts(
            "Extracting archive: #{archive_file}",
            true,
          )
          CliOutputFormatter.verbose_puts(
            "Output directory: #{output_dir}",
            true,
          )
          if patterns
            CliOutputFormatter.verbose_puts(
              "Include patterns: #{patterns.join(', ')}",
              true,
            )
          end
          if excludes
            CliOutputFormatter.verbose_puts(
              "Exclude patterns: #{excludes.join(', ')}",
              true,
            )
          end
          if regex
            CliOutputFormatter.verbose_puts(
              "Regex pattern: #{regex}",
              true,
            )
          end
        end

        start_time = Time.now

        file_count = if patterns || excludes || regex
                       extract_with_patterns(archive_file, output_dir, verbose)
                     else
                       extract_archive(archive_file, output_dir, verbose)
                     end

        elapsed = Time.now - start_time

        if verbose
          puts ""
          puts "Extraction completed successfully"
          puts "Files extracted: #{file_count}"
          puts "Time elapsed: #{elapsed.round(2)}s"
        else
          puts "Extracted #{file_count} file(s) to: #{output_dir}"
        end
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

      def extract_archive(archive_file, output_dir, verbose)
        reader = case File.extname(archive_file).downcase
                 when ".rar"
                   Formats::Rar::Reader.new(archive_file).open
                 when ".tar"
                   Formats::Tar::Reader.new(archive_file).read
                 when ".gz", ".gzip"
                   # GZIP files are single-file compression, extract directly
                   extract_gzip(archive_file, output_dir, verbose)
                   return 1
                 when ".bz2", ".bzip2"
                   # BZIP2 files are single-file compression, extract directly
                   extract_bzip2(archive_file, output_dir, verbose)
                   return 1
                 when ".xz"
                   # XZ files are single-file compression, extract directly
                   extract_xz(archive_file, output_dir, verbose)
                   return 1
                 else
                   Formats::SevenZip::Reader.new(archive_file).open
                 end
        file_count = 0

        reader.entries.each do |entry|
          output_path = File.join(output_dir, entry.name)

          if entry.directory?
            CliOutputFormatter.verbose_puts(
              "Creating directory: #{entry.name}",
              verbose,
            )
            FileUtils.mkdir_p(output_path)
          else
            CliOutputFormatter.verbose_puts(
              "Extracting: #{entry.name}",
              verbose,
            )

            # Ensure parent directory exists
            FileUtils.mkdir_p(File.dirname(output_path))

            # Extract file
            reader.extract_entry(entry.name, output_path)

            file_count += 1
          end
        end

        file_count
      rescue StandardError => e
        raise Omnizip::CompressionError,
              "Failed to extract archive: #{e.message}"
      end

      def extract_with_patterns(archive_file, output_dir, verbose)
        # Determine archive type and open appropriately
        archive = case File.extname(archive_file).downcase
                  when ".zip"
                    Omnizip::Zip::File.open(archive_file)
                  when ".rar"
                    Formats::Rar::Reader.new(archive_file).open
                  when ".tar"
                    Formats::Tar::Reader.new(archive_file).read
                  else
                    Formats::SevenZip::Reader.new(archive_file).open
                  end

        # Build filter chain
        filter = Extraction::FilterChain.new

        # Add include patterns
        if options[:pattern]
          Array(options[:pattern]).each do |pattern|
            filter.include_pattern(pattern)
          end
        end

        # Add regex pattern
        if options[:regex]
          filter.include_pattern(Regexp.new(options[:regex]))
        end

        # Add exclude patterns
        if options[:exclude]
          Array(options[:exclude]).each do |pattern|
            filter.exclude_pattern(pattern)
          end
        end

        # Extract with filter
        extract_options = {
          preserve_paths: !options[:flatten],
          flatten: options[:flatten] || false,
          overwrite: true,
        }

        extracted = Extraction.extract_with_filter(
          archive,
          filter,
          output_dir,
          extract_options,
        )

        if verbose
          extracted.each do |path|
            CliOutputFormatter.verbose_puts(
              "Extracted: #{File.basename(path)}",
              verbose,
            )
          end
        end

        extracted.size
      ensure
        archive&.close if archive.respond_to?(:close)
      end

      def extract_gzip(archive_file, output_dir, verbose)
        output_file = File.join(
          output_dir,
          File.basename(archive_file, ".*"),
        )
        CliOutputFormatter.verbose_puts(
          "Decompressing GZIP: #{archive_file}",
          verbose,
        )
        FileUtils.mkdir_p(output_dir)
        Formats::Gzip.decompress(archive_file, output_file)
      end

      def extract_bzip2(archive_file, output_dir, verbose)
        output_file = File.join(
          output_dir,
          File.basename(archive_file, ".*"),
        )
        CliOutputFormatter.verbose_puts(
          "Decompressing BZIP2: #{archive_file}",
          verbose,
        )
        FileUtils.mkdir_p(output_dir)
        Formats::Bzip2File.decompress(archive_file, output_file)
      end

      def extract_xz(archive_file, output_dir, verbose)
        output_file = File.join(
          output_dir,
          File.basename(archive_file, ".*"),
        )
        CliOutputFormatter.verbose_puts(
          "Decompressing XZ: #{archive_file}",
          verbose,
        )
        FileUtils.mkdir_p(output_dir)
        Formats::Xz.decompress(archive_file, output_file)
      end
    end
  end
end
