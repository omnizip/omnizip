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

    desc "compress INPUT OUTPUT", "Compress a file"
    long_desc <<~DESC
      Compress INPUT file and write the result to OUTPUT file.

      The compression algorithm and level can be specified with options.
      By default, LZMA compression is used with level 5.

      Examples:

        $ omnizip compress input.txt output.lzma

        $ omnizip compress input.txt output.lzma --level 9 --verbose
    DESC
    option :algorithm, type: :string, default: "lzma",
                       desc: "Compression algorithm to use"
    option :level, type: :numeric, default: 5,
                   desc: "Compression level (1-9)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def compress(input, output)
      Commands::CompressCommand.new(options).run(input, output)
    rescue StandardError => e
      handle_error(e)
    end

    desc "decompress INPUT OUTPUT", "Decompress a file"
    long_desc <<~DESC
      Decompress INPUT file and write the result to OUTPUT file.

      The algorithm will be auto-detected from the compressed file,
      or can be explicitly specified with the --algorithm option.

      Examples:

        $ omnizip decompress output.lzma restored.txt

        $ omnizip decompress output.lzma restored.txt --verbose
    DESC
    option :algorithm, type: :string,
                       desc: "Decompression algorithm (auto-detect if omitted)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def decompress(input, output)
      Commands::DecompressCommand.new(options).run(input, output)
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

    def handle_error(error)
      warn CliOutputFormatter.format_error(error)
      exit 1
    end
  end
end
