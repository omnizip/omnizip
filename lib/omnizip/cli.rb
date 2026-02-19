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
require_relative "commands/profile_list_command"
require_relative "commands/profile_show_command"
require_relative "commands/metadata_command"
require_relative "commands/archive_verify_command"
require_relative "commands/archive_repair_command"
require_relative "cli/output_formatter"

module Omnizip
  # Profile commands subcommand group
  class ProfileCommands < Thor
    class << self
      def exit_on_failure?
        true
      end
    end

    desc "list", "List available compression profiles"
    long_desc <<~DESC
      List all available compression profiles with their descriptions.

      Examples:

        $ omnizip profile list

        $ omnizip profile list --verbose
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Show detailed information"
    def list
      Omnizip::Commands::ProfileListCommand.new(options).run
    rescue StandardError => e
      handle_error(e)
    end

    desc "show PROFILE", "Show profile details"
    long_desc <<~DESC
      Show detailed information about a specific compression profile.

      PROFILE is the name of the profile to show.

      Examples:

        $ omnizip profile show maximum

        $ omnizip profile show fast
    DESC
    def show(profile_name)
      Omnizip::Commands::ProfileShowCommand.new(options).run(profile_name)
    rescue StandardError => e
      handle_error(e)
    end

    private

    def handle_error(error)
      warn Omnizip::CliOutputFormatter.format_error(error)
      exit 1
    end
  end

  # Archive commands subcommand group
  class ArchiveCommands < Thor
    class << self
      def exit_on_failure?
        true
      end
    end

    desc "create OUTPUT INPUT...", "Create .7z or .rar archive"
    long_desc <<~DESC
      Create a .7z or .rar archive from files and directories.

      OUTPUT is the path to the archive to create (.7z or .rar extension).
      INPUT can be one or more files or directories to archive.

      For split archives, OUTPUT should end with .001 (e.g., backup.7z.001).

      RAR5 archives are created using pure Ruby (no external tools needed).
      RAR5 currently supports individual files only (not directories).

      Examples:

        $ omnizip archive create archive.7z file1.txt file2.txt

        $ omnizip archive create archive.7z dir/ --algorithm lzma2 \\
          --level 9

        $ omnizip archive create archive.7z file.txt --no-solid \\
          --filters bcj_x86

        $ omnizip archive create backup.7z.001 large_data/ --volume-size 100M

        $ omnizip archive create backup.7z.001 files/ --volume-size 4.7GB

        $ omnizip archive create archive.rar file1.txt file2.txt

        $ omnizip archive create archive.rar data.txt --rar-compression lzma \\
          --level 5 --include-mtime --include-crc32

        $ omnizip archive create secure.rar data.txt --rar-compression lzma \\
          --level 5 --password "SecurePass123!" --kdf-iterations 262144

        $ omnizip archive create backup.rar files/ --rar-compression lzma \\
          --level 5 --solid --multi-volume --volume-size 100M

        $ omnizip archive create critical.rar data/ --rar-compression lzma \\
          --level 5 --password "Secure2025!" --recovery --recovery-percent 10
    DESC
    option :format, type: :string,
                    desc: "Archive format (7z or rar, default: auto-detect from extension)"
    option :profile, type: :string,
                     desc: "Compression profile (fast, balanced, maximum, text, binary, archive, auto)"
    option :algorithm, type: :string, default: "lzma2",
                       desc: "Compression algorithm for 7z (lzma, lzma2, ppmd7, bzip2)"
    option :level, type: :numeric, default: 5,
                   desc: "Compression level (1-9 for 7z, 1-5 for RAR5)"
    option :solid, type: :boolean, default: true,
                   desc: "Use solid compression (default: true for 7z, false for RAR)"
    option :filters, type: :string,
                     desc: "Filter chain for 7z (e.g., bcj_x86,delta)"
    option :volume_size, type: :string,
                         desc: "Volume size for split archives (e.g., 100M, 650MB, 4.7GB)"
    option :password, type: :string,
                      desc: "Password for encryption (7z: header encryption, RAR5: AES-256-CBC)"
    option :encrypt_headers, type: :boolean, default: false,
                             desc: "Encrypt archive headers (7z only, hides filenames)"
    option :preserve_ntfs_streams, type: :boolean, default: false,
                                   desc: "Preserve NTFS alternate data streams (Windows only, 7z only)"
    option :rar_version, type: :numeric, default: 5,
                         desc: "RAR version (4 or 5, default: 5 for pure Ruby)"
    option :rar_compression, type: :string, default: "store",
                             desc: "RAR compression method (store, lzma, auto)"
    option :include_mtime, type: :boolean, default: false,
                           desc: "Include modification time in RAR5 file headers"
    option :include_crc32, type: :boolean, default: false,
                           desc: "Include CRC32 checksum in RAR5 file headers"
    option :multi_volume, type: :boolean, default: false,
                          desc: "Create multi-volume RAR5 archive (requires --volume-size)"
    option :volume_naming, type: :string, default: "part",
                           desc: "Volume naming pattern for RAR5 (part, volume, numeric)"
    option :kdf_iterations, type: :numeric, default: 262_144,
                            desc: "PBKDF2 iterations for RAR5 encryption (65536-1048576, default: 262144)"
    option :recovery, type: :boolean, default: false,
                      desc: "Generate PAR2 recovery records for RAR5"
    option :recovery_percent, type: :numeric, default: 5,
                              desc: "PAR2 redundancy percentage for RAR5 (0-100, default: 5)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def create(output, *inputs)
      Omnizip::Commands::ArchiveCreateCommand.new(options).run(output, *inputs)
    rescue StandardError => e
      handle_error(e)
    end

    desc "extract ARCHIVE [OUTPUT_DIR]", "Extract archive"
    long_desc <<~DESC
      Extract a .7z, .zip, or .rar archive to a directory.

      ARCHIVE is the path to the archive to extract.
      OUTPUT_DIR is the directory to extract to (default: current directory).

      Pattern extraction options allow selective extraction of files.

      Examples:

        $ omnizip archive extract archive.zip

        $ omnizip archive extract archive.zip output/ --verbose

        $ omnizip archive extract archive.zip output/ --pattern '**/*.txt'

        $ omnizip archive extract archive.zip output/ \\
          --pattern '*.txt' --pattern '*.md'

        $ omnizip archive extract archive.zip output/ \\
          --pattern '**/*' --exclude '**/*.tmp' --exclude '**/test/**'

        $ omnizip archive extract archive.zip output/ \\
          --regex '\\.log$'

        $ omnizip archive extract archive.zip output/ \\
          --pattern 'src/**/*.rb' --flatten
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    option :pattern, type: :array,
                     desc: "Include pattern(s) for selective extraction"
    option :exclude, type: :array,
                     desc: "Exclude pattern(s) for selective extraction"
    option :regex, type: :string,
                   desc: "Regular expression pattern for selective extraction"
    option :flatten, type: :boolean, default: false,
                     desc: "Extract all files to output root (ignore paths)"
    option :count, type: :boolean, default: false,
                   desc: "Count matches without extracting"
    def extract(archive, output_dir = nil)
      Omnizip::Commands::ArchiveExtractCommand.new(options).run(archive,
                                                                output_dir)
    rescue StandardError => e
      handle_error(e)
    end

    desc "list ARCHIVE", "List archive contents"
    long_desc <<~DESC
      List the contents of a .7z, .zip, or .rar archive.

      ARCHIVE is the path to the archive to list.

      Pattern filtering options allow listing only matching files.

      Examples:

        $ omnizip archive list archive.zip

        $ omnizip archive list archive.zip --verbose

        $ omnizip archive list archive.zip --pattern '**/*.rb'

        $ omnizip archive list archive.zip --pattern '*.txt' --count
    DESC
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    option :pattern, type: :array,
                     desc: "Include pattern(s) for filtering"
    option :exclude, type: :array,
                     desc: "Exclude pattern(s) for filtering"
    option :count, type: :boolean, default: false,
                   desc: "Show count of matches"
    def list(archive)
      Omnizip::Commands::ArchiveListCommand.new(options).run(archive)
    rescue StandardError => e
      handle_error(e)
    end

    desc "metadata ARCHIVE [PATTERN]", "View or edit archive metadata"
    long_desc <<~DESC
      View or edit metadata for archives and entries.

      ARCHIVE is the path to the archive.
      PATTERN is an optional entry name or glob pattern.

      Examples:

        # View archive metadata
        $ omnizip archive metadata archive.zip --show

        # View entry metadata
        $ omnizip archive metadata archive.zip file.txt --show

        # Set archive comment
        $ omnizip archive metadata archive.zip --comment "My backup"

        # Set entry comment
        $ omnizip archive metadata archive.zip file.txt --comment "Important"

        # Set modification time
        $ omnizip archive metadata archive.zip file.txt --set-mtime now

        # Set permissions
        $ omnizip archive metadata archive.zip '*.rb' --chmod 755
    DESC
    option :show, type: :boolean, default: false,
                  desc: "Show metadata (read-only)"
    option :comment, type: :string,
                     desc: "Set comment"
    option :set_mtime, type: :string,
                       desc: "Set modification time (e.g., 'now', '2024-01-01')"
    option :chmod, type: :string,
                   desc: "Set Unix permissions (e.g., '755', '0644')"
    option :set_attribute, type: :string,
                           desc: "Set attribute flag (readonly, hidden, system, archive)"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def metadata(archive, pattern = nil)
      Omnizip::Commands::MetadataCommand.new(options).run(archive, pattern)
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

    desc "profile SUBCOMMAND ...ARGS", "Manage compression profiles"
    subcommand "profile", ProfileCommands

    desc "archive SUBCOMMAND ...ARGS", "Manage .7z archives"
    subcommand "archive", ArchiveCommands
    desc "convert SOURCE TARGET", "Convert archive between formats"
    long_desc <<~DESC
      Convert an archive from one format to another.

      SOURCE is the path to the source archive (ZIP, 7z, or RAR).
      TARGET is the path to the target archive (ZIP or 7z).
      Note: RAR can only be a source (read-only), not a target.

      Examples:

        $ omnizip convert archive.zip archive.7z

        $ omnizip convert archive.7z backup.zip

        $ omnizip convert archive.zip archive.7z --compression lzma2 --level 9

        $ omnizip convert archive.zip archive.7z --no-solid
    DESC
    option :compression, type: :string,
                         desc: "Compression algorithm (lzma, lzma2, ppmd7, bzip2)"
    option :level, type: :numeric, default: 5,
                   desc: "Compression level (1-9)"
    option :filter, type: :string,
                    desc: "Filter to apply (bcj-x86, delta, etc.)"
    option :solid, type: :boolean, default: true,
                   desc: "Use solid compression for 7z (default: true)"
    option :preserve_metadata, type: :boolean, default: true,
                               desc: "Preserve metadata (default: true)"
    option :delete_source, type: :boolean, default: false,
                           desc: "Delete source after conversion"
    option :verbose, type: :boolean, default: false,
                     aliases: "-v",
                     desc: "Enable verbose output"
    def convert(source, target)
      require_relative "converter"

      puts "Converting #{source} to #{target}..." if options[:verbose]

      result = Omnizip::Converter.convert(
        source,
        target,
        compression: options[:compression]&.to_sym,
        compression_level: options[:level],
        filter: options[:filter]&.to_sym,
        solid: options[:solid],
        preserve_metadata: options[:preserve_metadata],
        delete_source: options[:delete_source],
      )

      puts "Conversion complete!"
      puts "Source: #{result.source_path} (#{format_bytes(result.source_size)})"
      puts "Target: #{result.target_path} (#{format_bytes(result.target_size)})"
      puts "Size change: #{result.size_reduction.round(1)}%"
      puts "Duration: #{result.duration.round(2)}s"
      puts "Entries: #{result.entry_count}"

      if result.warnings?
        puts "\nWarnings:"
        result.warnings.each { |w| puts "  - #{w}" }
      end
    rescue StandardError => e
      handle_error(e)
    end

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
        level: options[:level],
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

    def format_bytes(bytes)
      return "0 B" if bytes.zero?

      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = [exp, units.size - 1].min

      "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
    end
  end
end
