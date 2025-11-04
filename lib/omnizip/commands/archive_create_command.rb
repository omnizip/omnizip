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

        # Apply profile settings if specified
        opts = options.dup
        if opts[:profile]
          first_file = find_first_file(inputs)
          opts = apply_profile(first_file, opts)
        end

        algorithm = (opts[:algorithm] || "lzma2").to_sym
        level = opts[:level] || 5
        solid = opts.fetch(:solid, true)
        verbose = opts[:verbose] || false
        filters = parse_filters(opts[:filters])
        volume_size = parse_volume_size(opts[:volume_size])
        password = opts[:password]
        encrypt_headers = opts[:encrypt_headers] || false
        preserve_ntfs_streams = opts[:preserve_ntfs_streams] || false

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
          if volume_size
            CliOutputFormatter.verbose_puts(
              "Volume size: #{format_bytes(volume_size)}",
              true
            )
          end
          unless filters.empty?
            CliOutputFormatter.verbose_puts(
              "Filters: #{filters.join(", ")}",
              true
            )
          end
          if encrypt_headers
            CliOutputFormatter.verbose_puts(
              "Header encryption: enabled",
              true
            )
          end
          if preserve_ntfs_streams && Omnizip::Platform.supports_ntfs_streams?
            CliOutputFormatter.verbose_puts(
              "NTFS streams: preserving",
              true
            )
          end
        end

        start_time = Time.now

        create_archive(output_file, inputs, algorithm, level, solid,
                       filters, volume_size, password, encrypt_headers,
                       preserve_ntfs_streams, verbose)

        elapsed = Time.now - start_time

        archive_size = calculate_archive_size(output_file, volume_size)

        if verbose
          puts ""
          puts "Archive created successfully"
          if volume_size
            puts "Total size: #{format_bytes(archive_size)}"
            puts "Volumes: #{count_volumes(output_file)}"
          else
            puts "Archive size: #{format_bytes(archive_size)}"
          end
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
                         filters, volume_size, password, encrypt_headers,
                         preserve_ntfs_streams, verbose)
        writer_opts = {
          algorithm: algorithm,
          level: level,
          solid: solid,
          filters: filters
        }
        writer_opts[:volume_size] = volume_size if volume_size
        writer_opts[:password] = password if password
        writer_opts[:encrypt_headers] = encrypt_headers if encrypt_headers

        writer = Formats::SevenZip::Writer.new(output_file, writer_opts)

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

      def apply_profile(file_path, options)
        profile_spec = options.delete(:profile)
        return options unless profile_spec

        # Get the profile
        profile = case profile_spec
                  when "auto"
                    file_path ? Omnizip::Profile.detect(file_path) : Omnizip::Profile.get(:balanced)
                  else
                    Omnizip::Profile.get(profile_spec.to_sym) || Omnizip::Profile.get(:balanced)
                  end

        # Apply profile to options
        profile.apply_to(options)
      end

      def find_first_file(inputs)
        inputs.each do |input|
          return input if File.file?(input)

          # Check directories for first file
          if File.directory?(input)
            Dir.foreach(input) do |entry|
              next if entry == "." || entry == ".."

              full_path = File.join(input, entry)
              return full_path if File.file?(full_path)
            end
          end
        end
        nil
      end

      def parse_volume_size(size_str)
        return nil if size_str.nil? || size_str.empty?

        require_relative "../models/split_options"
        Omnizip::Models::SplitOptions.parse_volume_size(size_str)
      end

      def calculate_archive_size(output_file, volume_size)
        if volume_size
          # Count all volumes
          base = output_file.sub(/\.\d{3}$/, "")
          total = 0
          volume_num = 1
          loop do
            volume_path = format("%s.%03d", base, volume_num)
            break unless File.exist?(volume_path)

            total += File.size(volume_path)
            volume_num += 1
          end
          total
        else
          File.size(output_file)
        end
      end

      def count_volumes(output_file)
        base = output_file.sub(/\.\d{3}$/, "")
        count = 0
        loop do
          volume_path = format("%s.%03d", base, count + 1)
          break unless File.exist?(volume_path)

          count += 1
        end
        count
      end
    end
  end
end
