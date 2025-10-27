# frozen_string_literal: true

module Omnizip
  # Temporary file management with automatic cleanup
  # Provides safe, atomic operations with RAII pattern
  module Temp
    # Configuration for temp file operations
    class Configuration
      attr_accessor :directory, :prefix, :cleanup_on_exit

      def initialize
        @directory = nil # Use system default (Dir.tmpdir)
        @prefix = "omniz_"
        @cleanup_on_exit = true
      end
    end

    class << self
      # Global configuration
      # @return [Configuration] Current configuration
      def configuration
        @configuration ||= Configuration.new
      end

      # Configure temp file operations
      # @yield [config] Configuration block
      def configure
        yield configuration
        setup_cleanup_hooks if configuration.cleanup_on_exit
      end

      # Create temporary file with automatic cleanup
      # @param prefix [String] Filename prefix
      # @param suffix [String] Filename suffix
      # @yield [path] Block called with temp file path
      # @return [Object] Block return value
      def file(prefix: nil, suffix: "", &block)
        prefix ||= configuration.prefix
        temp_file = TempFile.new(
          prefix: prefix,
          suffix: suffix,
          directory: configuration.directory
        )

        registry.track(temp_file)

        begin
          block.call(temp_file.path)
        ensure
          registry.untrack(temp_file)
          temp_file.unlink unless temp_file.kept?
        end
      end

      # Create temporary directory with automatic cleanup
      # @param prefix [String] Directory prefix
      # @yield [path] Block called with temp directory path
      # @return [Object] Block return value
      def directory(prefix: nil, &block)
        require "tmpdir"
        prefix ||= configuration.prefix

        Dir.mktmpdir(prefix, configuration.directory) do |dir|
          block.call(dir)
        end
      end

      # Create temporary archive with automatic cleanup
      # @param format [Symbol] Archive format (:zip, :seven_zip)
      # @yield [archive] Block called with archive helper
      # @return [Object] Block return value
      def with_archive(format: :zip, &block)
        suffix = format == :zip ? ".zip" : ".7z"

        file(suffix: suffix) do |path|
          archive = ArchiveHelper.new(path, format)
          block.call(archive)
        end
      end

      # Get temp file registry
      # @return [TempFileRegistry] Registry instance
      def registry
        @registry ||= TempFileRegistry.new
      end

      # Cleanup all tracked temp files
      def cleanup_all
        registry.cleanup_all
      end

      private

      def setup_cleanup_hooks
        return if @hooks_installed

        # AtExit handler for normal termination
        at_exit { cleanup_all }

        # Signal handlers for interruption
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            cleanup_all
            exit(1)
          end
        end

        @hooks_installed = true
      end
    end

    # Helper class for temp archive operations
    class ArchiveHelper
      attr_reader :path, :format

      def initialize(path, format)
        @path = path
        @format = format
      end

      # Add file to archive
      # @param name [String] Entry name
      # @param data [String] Entry data
      def add_file(name, data = nil, &block)
        data = block.call if block_given?

        case format
        when :zip
          require_relative "zip/file"
          Omnizip::Zip::File.create(path) do |zip|
            zip.add(name) { data }
          end
        end
      end
    end

    # Registry to track all temp files
    class TempFileRegistry
      def initialize
        @temp_files = []
        @mutex = Mutex.new
      end

      # Track a temp file
      # @param temp_file [TempFile] File to track
      def track(temp_file)
        @mutex.synchronize do
          @temp_files << temp_file
        end
      end

      # Untrack a temp file
      # @param temp_file [TempFile] File to untrack
      def untrack(temp_file)
        @mutex.synchronize do
          @temp_files.delete(temp_file)
        end
      end

      # Cleanup all tracked files
      def cleanup_all
        @mutex.synchronize do
          @temp_files.each do |temp_file|
            temp_file.unlink
          rescue StandardError
            nil
          end
          @temp_files.clear
        end
      end

      # Get count of tracked files
      # @return [Integer] Number of tracked files
      def count
        @mutex.synchronize { @temp_files.size }
      end
    end
  end
end

require_relative "temp/temp_file"
require_relative "temp/temp_file_pool"
require_relative "temp/safe_extract"
