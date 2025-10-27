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

        if verbose
          CliOutputFormatter.verbose_puts(
            "Extracting archive: #{archive_file}",
            true
          )
          CliOutputFormatter.verbose_puts(
            "Output directory: #{output_dir}",
            true
          )
        end

        start_time = Time.now

        file_count = extract_archive(archive_file, output_dir, verbose)

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
        reader = Formats::SevenZip::Reader.new(archive_file).open
        file_count = 0

        reader.entries.each do |entry|
          output_path = File.join(output_dir, entry.name)

          if entry.directory?
            CliOutputFormatter.verbose_puts(
              "Creating directory: #{entry.name}",
              verbose
            )
            FileUtils.mkdir_p(output_path)
          else
            CliOutputFormatter.verbose_puts(
              "Extracting: #{entry.name}",
              verbose
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
    end
  end
end
