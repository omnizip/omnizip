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

require "thor"
require_relative "commands/compress_command"
require_relative "commands/decompress_command"
require_relative "commands/list_command"
require_relative "commands/archive_create_command"
require_relative "commands/archive_extract_command"
require_relative "commands/archive_list_command"
require_relative "cli/output_formatter"

module Omnizip
  # Archive commands subcommand group
  class ArchiveCommands < Thor
    class << self
      def exit_on_failure?
        true
      end
    end

    desc "create OUTPUT INPUT...", "Create .7z archive"
    long_desc <<~DESC
      Create a .7z archive from files and directories.

      OUTPUT is the path to the .7z archive to create.
      INPUT can be one or more files or directories to archive.

      Examples:

        $ omnizip archive create archive.7z file1.txt file2.txt

        $ omnizip archive create archive.7z dir/ --algorithm lzma2 \\
          --level 9

        $ omnizip archive create archive.7z file.txt --no-solid \\
          --filters bcj_x86
    DESC
    option :algorithm, type: :string, default: "lzma2",
                       desc: "Compression algorithm (lzma, lzma2, ppmd7, bzip2)"
    option :level, type: :numeric, default: 5,
                   desc: "Compression level (1-9)"
    option :solid, type: :boolean, default: true,
                   desc: "Use solid compression (default: true)"
    option :filters, type: :string,
                     desc: "Filter chain (e.g., bcj_x86,delta)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def create(output, *inputs)
      Omnizip::Commands::ArchiveCreateCommand.new(options).run(output, *inputs)
    rescue StandardError => e
      handle_error(e)
    end

    desc "extract ARCHIVE [OUTPUT_DIR]", "Extract .7z archive"
    long_desc <<~DESC
      Extract a .7z archive to a directory.

      ARCHIVE is the path to the .7z archive to extract.
      OUTPUT_DIR is the directory to extract to (default: current directory).

      Examples:

        $ omnizip archive extract archive.7z

        $ omnizip archive extract archive.7z output/ --verbose
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def extract(archive, output_dir = nil)
      Omnizip::Commands::ArchiveExtractCommand.new(options).run(archive,
                                                                output_dir)
    rescue StandardError => e
      handle_error(e)
    end

    desc "list ARCHIVE", "List .7z archive contents"
    long_desc <<~DESC
      List the contents of a .7z archive.

      ARCHIVE is the path to the .7z archive to list.

      Examples:

        $ omnizip archive list archive.7z

        $ omnizip archive list archive.7z --verbose
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def list(archive)
      Omnizip::Commands::ArchiveListCommand.new(options).run(archive)
    rescue StandardError => e
      handle_error(e)
    end

    private

    def handle_error(error)
      warn Omnizip::CliOutputFormatter.format_error(error)
      exit 1
    end
  end

  # Command-line interface for Omnizip.
  #
  # Provides Thor-based CLI commands for compressing and decompressing
  # files using various compression algorithms.
  class Cli < Thor
    class << self
      def exit_on_failure?
        true
      end
    end

    desc "compress INPUT OUTPUT", "Compress a file or stream"
    long_desc <<~DESC
      Compress INPUT file and write the result to OUTPUT file.

      Use '-' for INPUT to read from stdin or OUTPUT to write to stdout.
      This enables Unix pipeline integration for streaming workflows.

      The compression algorithm and level can be specified with options.
      By default, LZMA compression is used with level 5.

      Examples:

        $ omnizip compress input.txt output.lzma

        $ omnizip compress input.txt output.lzma --level 9 --verbose

        $ cat input.txt | omnizip compress - output.zip --format zip

        $ omnizip compress input.txt - --format zip > output.zip

        $ cat data.txt | omnizip compress - - --format zip > out.zip
    DESC
    option :algorithm, type: :string, default: "lzma",
                       desc: "Compression algorithm to use"
    option :format, type: :string, default: nil,
                    desc: "Archive format (zip, 7z) - enables pipe mode"
    option :level, type: :numeric, default: 5,
                   desc: "Compression level (1-9)"
    option :entry_name, type: :string, default: nil,
                        desc: "Entry name in archive (pipe mode only)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def compress(input, output)
      # Pipe mode: use streaming compression
      if Omnizip::Pipe.stdin?(input) || Omnizip::Pipe.stdout?(output)
        compress_pipe(input, output)
      else
        Commands::CompressCommand.new(options).run(input, output)
      end
    rescue StandardError => e
      handle_error(e)
    end

    desc "decompress INPUT OUTPUT", "Decompress a file or stream"
    long_desc <<~DESC
      Decompress INPUT file and write the result to OUTPUT file or directory.

      Use '-' for INPUT to read from stdin. If OUTPUT is a directory,
      extracts all files. If OUTPUT is '-', streams first file to stdout.

      The algorithm will be auto-detected from the compressed file,
      or can be explicitly specified with the --algorithm option.

      Examples:

        $ omnizip decompress output.lzma restored.txt

        $ omnizip decompress output.lzma restored.txt --verbose

        $ cat archive.zip | omnizip decompress - extracted/

        $ omnizip decompress - - < archive.zip > output.txt

        $ cat archive.zip | omnizip decompress - extracted/ --verbose
    DESC
    option :algorithm, type: :string,
                       desc: "Decompression algorithm (auto-detect if omitted)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def decompress(input, output)
      # Pipe mode: use streaming decompression
      if Omnizip::Pipe.stdin?(input) || Omnizip::Pipe.stdout?(output)
        decompress_pipe(input, output)
      else
        Commands::DecompressCommand.new(options).run(input, output)
      end
    rescue StandardError => e
      handle_error(e)
    end

    desc "list", "List available compression algorithms"
    long_desc <<~DESC
      List all registered compression algorithms with their metadata.

      Displays algorithm name, description, and version information.

      Example:

        $ omnizip list
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def list
      Commands::ListCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc "version", "Display version information"
    def version
      puts "Omnizip v#{Omnizip::VERSION}"
      puts "Pure Ruby implementation of LZMA compression"
    end

    desc "archive SUBCOMMAND ...ARGS", "Manage .7z archives"
    subcommand "archive", ArchiveCommands

    map %w[-v --version] => :version

    private

    def compress_pipe(input, output)
      input_io = input == "-" ? $stdin : File.open(input, "rb")
      output_io = output == "-" ? $stdout : File.open(output, "wb")

      format = (options[:format] || :zip).to_sym
      compression = options[:algorithm]&.to_sym
      entry_name = options[:entry_name] || File.basename(input == "-" ? "stream.dat" : input)

      if options[:verbose]
        warn "Compressing from #{input == '-' ? 'stdin' : input} to #{output == '-' ? 'stdout' : output}"
        warn "Format: #{format}, Entry: #{entry_name}"
      end

      Omnizip::Pipe.compress(
        input_io,
        output_io,
        format: format,
        compression: compression,
        entry_name: entry_name,
        level: options[:level]
      )

      warn "Compression complete" if options[:verbose]
    ensure
      input_io.close if input_io && input != "-"
      output_io.close if output_io && output != "-"
    end

    def decompress_pipe(input, output)
      input_io = input == "-" ? $stdin : File.open(input, "rb")

      if options[:verbose]
        warn "Decompressing from #{input == '-' ? 'stdin' : input}"
      end

      if output == "-"
        # Stream to stdout
        Omnizip::Pipe.decompress(input_io, output: $stdout)
      else
        # Extract to directory
        Omnizip::Pipe.decompress(input_io, output_dir: output)
      end

      warn "Decompression complete" if options[:verbose]
    ensure
      input_io.close if input_io && input != "-"
    end

    def handle_error(error)
      warn CliOutputFormatter.format_error(error)
      exit 1
    end
  end
end
