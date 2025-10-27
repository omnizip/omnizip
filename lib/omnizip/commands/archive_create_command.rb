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
require_relative "../formats/seven_zip/writer"

module Omnizip
  module Commands
    # Command to create .7z archives from files and directories.
    class ArchiveCreateCommand
      attr_reader :options

      # Initialize archive create command with options.
      #
      # @param options [Hash] Command options from Thor
      def initialize(options = {})
        @options = options
      end

      # Execute the archive create command.
      #
      # @param output_file [String] Path to output .7z archive
      # @param inputs [Array<String>] Paths to files/directories to archive
      # @return [void]
      def run(output_file, *inputs)
        validate_inputs(output_file, inputs)

        algorithm = (options[:algorithm] || "lzma2").to_sym
        level = options[:level] || 5
        solid = options.fetch(:solid, true)
        verbose = options[:verbose] || false
        filters = parse_filters(options[:filters])

        if verbose
          CliOutputFormatter.verbose_puts(
            "Creating archive: #{output_file}",
            true
          )
          CliOutputFormatter.verbose_puts(
            "Algorithm: #{algorithm}, Level: #{level}, " \
            "Solid: #{solid}",
            true
          )
          unless filters.empty?
            CliOutputFormatter.verbose_puts(
              "Filters: #{filters.join(", ")}",
              true
            )
          end
        end

        start_time = Time.now

        create_archive(output_file, inputs, algorithm, level, solid,
                       filters, verbose)

        elapsed = Time.now - start_time

        archive_size = File.size(output_file)

        if verbose
          puts ""
          puts "Archive created successfully"
          puts "Archive size: #{format_bytes(archive_size)}"
          puts "Time elapsed: #{elapsed.round(2)}s"
        else
          puts "Created: #{output_file}"
        end
      end

      private

      def validate_inputs(output_file, inputs)
        raise Omnizip::IOError, "No input files specified" if
          inputs.empty?

        inputs.each do |input|
          unless File.exist?(input)
            raise Omnizip::IOError, "Input not found: #{input}"
          end
        end

        output_dir = File.dirname(output_file)
        unless File.directory?(output_dir)
          raise Omnizip::IOError,
                "Output directory does not exist: #{output_dir}"
        end

        return if File.writable?(output_dir)

        raise Omnizip::IOError,
              "Output directory not writable: #{output_dir}"
      end

      def parse_filters(filter_str)
        return [] if filter_str.nil? || filter_str.empty?

        filter_str.split(",").map(&:strip).map(&:to_sym)
      end

      def create_archive(output_file, inputs, algorithm, level, solid,
                         filters, verbose)
        writer = Formats::SevenZip::Writer.new(
          output_file,
          algorithm: algorithm,
          level: level,
          solid: solid,
          filters: filters
        )

        inputs.each do |input|
          if File.directory?(input)
            CliOutputFormatter.verbose_puts(
              "Adding directory: #{input}",
              verbose
            )
            writer.add_directory(input)
          else
            CliOutputFormatter.verbose_puts(
              "Adding file: #{input}",
              verbose
            )
            writer.add_file(input)
          end
        end

        CliOutputFormatter.verbose_puts("Writing archive...", verbose)
        writer.write
      rescue StandardError => e
        raise Omnizip::CompressionError,
              "Failed to create archive: #{e.message}"
      end

      def format_bytes(bytes)
        units = %w[B KB MB GB]
        size = bytes.to_f
        unit_idx = 0

        while size >= 1024 && unit_idx < units.length - 1
          size /= 1024.0
          unit_idx += 1
        end

        format("%.2f %s", size, units[unit_idx])
      end
    end
  end
end
