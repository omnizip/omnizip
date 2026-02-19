# frozen_string_literal: true

require "English"
require_relative "../platform"

module Omnizip
  module Platform
    # NTFS Alternate Data Streams handler
    # Windows-only feature for managing file alternate streams
    module NtfsStreams
      # Check if NTFS streams are available
      #
      # @return [Boolean] true if available
      def self.available?
        Platform.supports_ntfs_streams?
      end

      # List alternate data streams for a file
      #
      # @param file_path [String] Path to file
      # @return [Array<String>] List of stream names
      def self.list_streams(file_path)
        return [] unless available?
        return [] unless File.exist?(file_path)

        streams = []

        begin
          # Use PowerShell to list streams
          cmd = "powershell -Command \"Get-Item '#{file_path}' -Stream * | " \
                "Select-Object -ExpandProperty Stream\""
          output = `#{cmd} 2>&1`

          if $CHILD_STATUS.success?
            streams = output.lines.map(&:strip).reject do |s|
              s.empty? || s == ":$DATA"
            end
          end
        rescue StandardError => e
          warn "Failed to list NTFS streams: #{e.message}" if ENV["DEBUG"]
        end

        streams
      end

      # Read alternate data stream
      #
      # @param file_path [String] Path to file
      # @param stream_name [String] Stream name
      # @return [String, nil] Stream content or nil
      def self.read_stream(file_path, stream_name)
        return nil unless available?
        return nil unless File.exist?(file_path)

        begin
          # Read using alternate stream syntax: file.txt:StreamName
          stream_path = "#{file_path}:#{stream_name}"
          File.binread(stream_path)
        rescue Errno::ENOENT, Errno::EINVAL
          nil
        rescue StandardError => e
          warn "Failed to read NTFS stream: #{e.message}" if ENV["DEBUG"]
          nil
        end
      end

      # Write alternate data stream
      #
      # @param file_path [String] Path to file
      # @param stream_name [String] Stream name
      # @param data [String] Stream data
      # @return [Boolean] true if successful
      def self.write_stream(file_path, stream_name, data)
        return false unless available?
        return false unless File.exist?(file_path)

        begin
          # Write using alternate stream syntax: file.txt:StreamName
          stream_path = "#{file_path}:#{stream_name}"
          File.binwrite(stream_path, data)
          true
        rescue StandardError => e
          warn "Failed to write NTFS stream: #{e.message}" if ENV["DEBUG"]
          false
        end
      end

      # Delete alternate data stream
      #
      # @param file_path [String] Path to file
      # @param stream_name [String] Stream name
      # @return [Boolean] true if successful
      def self.delete_stream(file_path, stream_name)
        return false unless available?
        return false unless File.exist?(file_path)

        begin
          # Use PowerShell to remove stream
          cmd = "powershell -Command \"Remove-Item -Path '#{file_path}' " \
                "-Stream '#{stream_name}'\""
          system(cmd)
          $CHILD_STATUS.success?
        rescue StandardError => e
          warn "Failed to delete NTFS stream: #{e.message}" if ENV["DEBUG"]
          false
        end
      end

      # Copy all alternate streams from source to destination
      #
      # @param source_path [String] Source file
      # @param dest_path [String] Destination file
      # @return [Integer] Number of streams copied
      def self.copy_streams(source_path, dest_path)
        return 0 unless available?
        return 0 unless File.exist?(source_path)
        return 0 unless File.exist?(dest_path)

        copied = 0
        streams = list_streams(source_path)

        streams.each do |stream|
          next if stream == "$DATA" # Skip main data stream

          data = read_stream(source_path, stream)
          copied += 1 if data && write_stream(dest_path, stream, data)
        end

        copied
      end

      # Get stream information
      #
      # @param file_path [String] Path to file
      # @param stream_name [String] Stream name
      # @return [Hash, nil] Stream info or nil
      def self.stream_info(file_path, stream_name)
        return nil unless available?
        return nil unless File.exist?(file_path)

        data = read_stream(file_path, stream_name)
        return nil unless data

        {
          name: stream_name,
          size: data.bytesize,
          exists: true,
        }
      end

      # Check if file has any alternate streams
      #
      # @param file_path [String] Path to file
      # @return [Boolean] true if has streams
      def self.has_streams?(file_path)
        return false unless available?

        streams = list_streams(file_path)
        streams.any? { |s| s != "$DATA" }
      end

      # Archive streams to a hash
      #
      # @param file_path [String] Path to file
      # @return [Hash<String, String>] Stream name => data
      def self.archive_streams(file_path)
        return {} unless available?

        streams_data = {}
        streams = list_streams(file_path)

        streams.each do |stream|
          next if stream == "$DATA"

          data = read_stream(file_path, stream)
          streams_data[stream] = data if data
        end

        streams_data
      end

      # Restore streams from hash
      #
      # @param file_path [String] Path to file
      # @param streams_data [Hash<String, String>] Stream name => data
      # @return [Integer] Number of streams restored
      def self.restore_streams(file_path, streams_data)
        return 0 unless available?
        return 0 unless File.exist?(file_path)

        restored = 0

        streams_data.each do |stream_name, data|
          restored += 1 if write_stream(file_path, stream_name, data)
        end

        restored
      end
    end
  end
end
