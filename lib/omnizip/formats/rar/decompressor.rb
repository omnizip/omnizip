# frozen_string_literal: true

require "English"
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
            raise "RAR extraction not available" unless available?

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
            raise "RAR extraction not available" unless available?

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
            raise "RAR extraction not available" unless available?

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
            ["unrar", "/usr/bin/unrar", "/usr/local/bin/unrar"].each do |cmd|
              return cmd if system("which #{cmd} > /dev/null 2>&1")
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

            output = `#{command_path} 2>&1`
            output.match(/UNRAR\s+([\d.]+)/i)&.captures&.first || "unknown"
          end

          # Extract with unrar gem
          def extract_with_gem(archive_path, output_dir, password)
            require "unrar"
            Unrar.extract(archive_path, output_dir, password: password)
          rescue StandardError => e
            raise "Gem extraction failed: #{e.message}"
          end

          # Extract with system command
          def extract_with_command(archive_path, output_dir, password)
            cmd = build_extract_command(archive_path, output_dir, password)
            return if system(cmd)

            raise "Command extraction failed: #{archive_path}"
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
            raise "Gem listing failed: #{e.message}"
          end

          # List with system command
          def list_with_command(archive_path)
            output = `#{command_path} vb "#{archive_path}" 2>&1`
            raise "Command listing failed" unless $CHILD_STATUS.success?

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
          def extract_entry_with_command(archive_path, entry_name,
                                         output_path, password)
            temp_dir = Dir.mktmpdir
            cmd = build_extract_command(archive_path, temp_dir, password)
            unless system(cmd)
              raise "Command entry extraction failed: #{entry_name}"
            end

            source = File.join(temp_dir, entry_name)
            FileUtils.mv(source, output_path) if File.exist?(source)
          ensure
            FileUtils.rm_rf(temp_dir) if temp_dir
          end

          # Build extract command
          def build_extract_command(archive_path, output_dir, password)
            cmd = "#{command_path} x -y"
            cmd += " -p#{password}" if password
            cmd += " \"#{archive_path}\" \"#{output_dir}/\""
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
