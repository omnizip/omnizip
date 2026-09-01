# frozen_string_literal: true

require "English"
require "fileutils"
require "tmpdir"
module Omnizip
  module Formats
    module Rar
      # RAR decompressor wrapper
      # Provides fallback chain: unrar gem → system command → error
      class Decompressor
        class << self
          # Check if RAR decompression is available
          #
          # @return [Boolean] true if available
          def available?
            gem_available? || command_available?
          end

          # Get decompressor information
          #
          # @return [Hash] Decompressor type and version
          def info
            if gem_available?
              { type: :gem, version: gem_version }
            elsif command_available?
              { type: :command, version: command_version }
            else
              { type: :none, version: nil }
            end
          end

          # Check if unrar gem is available
          #
          # @return [Boolean] true if gem available
          def gem_available?
            require "unrar"
            true
          rescue LoadError
            false
          end

          # Check if system unrar command is available
          #
          # @return [Boolean] true if command available
          def command_available?
            !command_path.nil?
          end

          # Get unrar command path
          #
          # @return [String, nil] Path to unrar or nil
          def command_path
            @command_path ||= find_command
          end

          # Extract RAR archive to directory
          #
          # @param archive_path [String] Path to RAR archive
          # @param output_dir [String] Output directory
          # @param password [String, nil] Optional password
          # @raise [RuntimeError] if extraction fails
          def extract(archive_path, output_dir, password: nil)
            raise Omnizip::RarNotAvailableError, "RAR extraction not available" unless available?

            if gem_available?
              extract_with_gem(archive_path, output_dir, password)
            elsif command_available?
              extract_with_command(archive_path, output_dir, password)
            else
              raise unsupported_error
            end
          end

          # List RAR archive contents
          #
          # @param archive_path [String] Path to RAR archive
          # @return [Array<Hash>] Entry information
          # @raise [RuntimeError] if listing fails
          def list(archive_path)
            raise Omnizip::RarNotAvailableError, "RAR extraction not available" unless available?

            if gem_available?
              list_with_gem(archive_path)
            elsif command_available?
              list_with_command(archive_path)
            else
              raise unsupported_error
            end
          end

          # Extract single entry from RAR
          #
          # @param archive_path [String] Path to RAR archive
          # @param entry_name [String] Entry name
          # @param output_path [String] Output path
          # @param password [String, nil] Optional password
          def extract_entry(archive_path, entry_name, output_path,
                            password: nil)
            raise Omnizip::RarNotAvailableError, "RAR extraction not available" unless available?

            if gem_available?
              extract_entry_with_gem(archive_path, entry_name,
                                     output_path, password)
            elsif command_available?
              extract_entry_with_command(archive_path, entry_name,
                                         output_path, password)
            else
              raise unsupported_error
            end
          end

          private

          # Find unrar command
          #
          # @return [String, nil] Command path or nil
          def find_command
            if Gem.win_platform?
              find_command_windows
            else
              find_command_unix
            end
          end

          # Find unrar command on Unix
          #
          # @return [String, nil] Command path or nil
          def find_command_unix
            ["unrar", "/usr/bin/unrar", "/usr/local/bin/unrar"].each do |cmd|
              return cmd if system("which #{cmd} > #{File::NULL} 2>&1")
            end
            nil
          end

          # Find unrar command on Windows
          #
          # @return [String, nil] Command path or nil
          def find_command_windows
            # Check for unrar in PATH
            ["UnRAR.exe", "unrar.exe"].each do |cmd|
              return cmd if system("where #{cmd} > #{File::NULL} 2>&1")
            end

            # Check common WinRAR install locations
            [
              File.join(ENV.fetch("ProgramFiles", 'C:\Program Files'),
                        "WinRAR", "UnRAR.exe"),
              File.join(
                ENV.fetch("ProgramFiles(x86)",
                          'C:\Program Files (x86)'),
                "WinRAR", "UnRAR.exe"
              ),
            ].each do |path|
              return path if File.exist?(path)
            end

            nil
          end

          # Get gem version
          #
          # @return [String] Version string
          def gem_version
            require "unrar"
            begin
              Unrar::VERSION
            rescue StandardError
              "unknown"
            end
          end

          # Get command version
          #
          # @return [String] Version string
          def command_version
            return nil unless command_available?

            output = `"#{command_path}" 2>&1`
            output.match(/UNRAR\s+([\d.]+)/i)&.captures&.first || "unknown"
          end

          # Extract with unrar gem
          def extract_with_gem(archive_path, output_dir, password)
            require "unrar"
            Unrar.extract(archive_path, output_dir, password: password)
          rescue StandardError => e
            raise Omnizip::DecompressionError, "Gem extraction failed: #{e.message}"
          end

          # Extract with system command
          def extract_with_command(archive_path, output_dir, password)
            cmd = build_extract_command(archive_path, output_dir, password)
            return if system(*cmd)

            raise Omnizip::DecompressionError, "Command extraction failed: #{archive_path}"
          end

          # List with unrar gem
          def list_with_gem(archive_path)
            require "unrar"
            archive = Unrar::Archive.new(archive_path)
            archive.list.map do |entry|
              {
                name: entry.filename,
                size: entry.unpacked_size,
                compressed_size: entry.packed_size,
                is_dir: entry.directory?,
                mtime: entry.file_time,
              }
            end
          rescue StandardError => e
            raise Omnizip::DecompressionError, "Gem listing failed: #{e.message}"
          end

          # List with system command
          def list_with_command(archive_path)
            output = `"#{command_path}" vb "#{archive_path}" 2>&1`
            raise Omnizip::DecompressionError, "Command listing failed" unless $CHILD_STATUS.success?

            output.split("\n").map do |line|
              { name: line.strip, size: 0, compressed_size: 0,
                is_dir: false, mtime: nil }
            end
          end

          # Extract entry with gem
          def extract_entry_with_gem(archive_path, entry_name,
                                     output_path, password)
            require "unrar"
            archive = Unrar::Archive.new(archive_path)
            archive.extract_to_file(entry_name, output_path,
                                    password: password)
          rescue StandardError => e
            raise "Gem entry extraction failed: #{e.message}"
          end

          # Extract entry with command
          #
          # unrar cannot extract a single entry without walking the
          # archive, so the archive spills to a cache directory ONCE
          # per archive path; subsequent extractions copy out of the
          # cache instead of re-running unrar over the whole file.
          def extract_entry_with_command(archive_path, entry_name,
                                         output_path, password)
            cache_key = begin
              File.realpath(archive_path)
            rescue StandardError
              archive_path
            end

            cached_dir = extract_cache[cache_key]
            unless cached_dir
              cached_dir = Dir.mktmpdir("omnizip_unrar")
              cmd = build_extract_command(archive_path, cached_dir, password)
              unless system(*cmd)
                FileUtils.rm_rf(cached_dir)
                raise "Command entry extraction failed: #{entry_name}"
              end
              extract_cache[cache_key] = cached_dir
              install_exit_sweeper
            end

            source = File.join(cached_dir, entry_name)
            FileUtils.cp(source, output_path) if File.exist?(source)
          end

          # Extracted-archive cache: archive path => spill directory.
          # Cleared by .clear_extract_cache!; an at_exit sweeper
          # reclaims everything at normal process termination.
          def extract_cache
            @extract_cache ||= {}
          end

          # Drop the extraction cache and remove its directories
          def clear_extract_cache!
            extract_cache.each_value { |dir| FileUtils.rm_rf(dir) }
            extract_cache.clear
          end

          # Reclaim spill directories when the process exits normally
          def install_exit_sweeper
            return if @exit_sweeper_installed

            at_exit { clear_extract_cache! }
            @exit_sweeper_installed = true
          end

          # Build extract command
          def build_extract_command(archive_path, output_dir, password)
            # Array form: no shell involved, so paths and passwords
            # with special characters stay literal. -idq silences the
            # per-file progress banner.
            cmd = [command_path, "x", "-idq", "-y"]
            cmd << "-p#{password}" if password
            cmd << archive_path
            cmd << "#{output_dir}/"
            cmd
          end

          # Unsupported error message
          def unsupported_error
            <<~ERROR
              RAR extraction not available.

              To enable RAR support, install one of:
              1. unrar gem: gem install unrar
              2. System unrar: brew install unrar (macOS) or
                 apt-get install unrar (Linux)
            ERROR
          end
        end
      end
    end
  end
end
