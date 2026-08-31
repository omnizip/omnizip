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
      # @param output_file [String] Path to output archive
      # @param inputs [Array<String>] Paths to files/directories to archive
      # @return [void]
      # Execute the archive create command.
      #
      # Routes through the Archive facade: the handler registry
      # picks each format's writer and applies its option semantics,
      # so this command only translates CLI vocabulary and reports.
      #
      # @param output_file [String] Path to output archive
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

        format = (opts[:format] || detect_format(output_file)).to_sym
        handler_opts = handler_options(format, opts)
        verbose = opts[:verbose] || false

        announce(output_file, format, handler_opts, opts, verbose)

        start_time = Time.now

        Omnizip::Archive.create(output_file, format: format,
                                             **handler_opts) do |archive|
          inputs.each do |input|
            if File.directory?(input)
              CliOutputFormatter.verbose_puts(
                "Adding directory: #{input}",
                verbose,
              )
              archive.add_directory(input)
            else
              CliOutputFormatter.verbose_puts(
                "Adding file: #{input}",
                verbose,
              )
              archive.add_file(input)
            end
          end
        end

        elapsed = Time.now - start_time
        archive_size = calculate_archive_size(output_file,
                                              handler_opts[:volume_size])

        if verbose
          puts ""
          puts "Archive created successfully"
          if handler_opts[:volume_size]
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

      def detect_format(filename)
        case File.extname(filename).downcase
        when ".rar" then :rar
        else :seven_zip
        end
      end

      # Translate the format-agnostic CLI vocabulary into the option
      # keywords each format's writer understands; nil values drop
      def handler_options(format, opts)
        case format
        when :rar
          rar_options(opts)
        else
          seven_zip_options(opts)
        end
      end

      def rar_options(opts)
        {
          version: opts[:rar_version],
          compression: opts[:rar_compression]&.to_sym,
          level: opts[:level],
          include_mtime: opts[:include_mtime],
          include_crc32: opts[:include_crc32],
          solid: opts[:solid],
          multi_volume: opts[:multi_volume],
          volume_size: opts[:volume_size],
          volume_naming: opts[:volume_naming],
          password: opts[:password],
          kdf_iterations: opts[:kdf_iterations],
          recovery: opts[:recovery],
          recovery_percent: opts[:recovery_percent],
        }.compact
      end

      def seven_zip_options(opts)
        {
          algorithm: (opts[:algorithm] || "lzma2").to_sym,
          level: opts[:level] || 5,
          solid: opts.fetch(:solid, true),
          filters: parse_filters(opts[:filters]),
          volume_size: parse_volume_size(opts[:volume_size]),
          password: opts[:password],
          encrypt_headers: opts[:encrypt_headers] || false,
        }.compact
      end

      def announce(output_file, format, handler_opts, _opts, verbose)
        return unless verbose

        CliOutputFormatter.verbose_puts(
          "Creating archive: #{output_file}",
          true,
        )
        CliOutputFormatter.verbose_puts(
          "Format: #{format == :rar ? "RAR#{handler_opts[:version] || 5}" : '7z'}, " \
          "Algorithm: #{handler_opts[:algorithm] || handler_opts[:compression]}, " \
          "Level: #{handler_opts[:level]}, Solid: #{handler_opts[:solid]}",
          true,
        )
        if handler_opts[:volume_size]
          CliOutputFormatter.verbose_puts(
            "Volume size: #{format_bytes(handler_opts[:volume_size])}",
            true,
          )
        end
        if handler_opts[:password]
          CliOutputFormatter.verbose_puts(
            "Encryption: enabled",
            true,
          )
        end
      end

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
              next if [".", ".."].include?(entry)

              full_path = File.join(input, entry)
              return full_path if File.file?(full_path)
            end
          end
        end
        nil
      end

      def parse_volume_size(size_str)
        return nil if size_str.nil? || size_str.empty?

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
