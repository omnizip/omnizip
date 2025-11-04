# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module Progress
    # Represents the current state of an operation's progress.
    #
    # This class stores all data about the current progress of an operation,
    # including file counts, byte counts, current file being processed,
    # and calculated percentages.
    class OperationProgress
      attr_reader :total_files, :total_bytes, :files_done, :bytes_done,
                  :current_file, :start_time

      # Initialize a new operation progress tracker
      #
      # @param total_files [Integer] Total number of files to process
      # @param total_bytes [Integer] Total bytes to process
      def initialize(total_files:, total_bytes:)
        @total_files = total_files
        @total_bytes = total_bytes
        @files_done = 0
        @bytes_done = 0
        @current_file = nil
        @start_time = Time.now
      end

      # Update progress with new values
      #
      # @param files [Integer] Number of files completed
      # @param bytes [Integer] Number of bytes processed
      # @param current_file [String] Name of file currently processing
      def update(files:, bytes:, current_file: nil)
        @files_done = files
        @bytes_done = bytes
        @current_file = current_file
      end

      # Calculate overall percentage complete
      #
      # @return [Float] Percentage complete (0.0-100.0)
      def percentage
        return 0.0 if total_bytes.zero?

        (bytes_done.to_f / total_bytes * 100.0).round(1)
      end

      # Calculate percentage of files complete
      #
      # @return [Float] Percentage of files complete (0.0-100.0)
      def files_percent
        return 0.0 if total_files.zero?

        (files_done.to_f / total_files * 100.0).round(1)
      end

      # Calculate percentage of bytes complete
      #
      # @return [Float] Percentage of bytes complete (0.0-100.0)
      def bytes_percent
        return 0.0 if total_bytes.zero?

        (bytes_done.to_f / total_bytes * 100.0).round(1)
      end

      # Get elapsed time in seconds
      #
      # @return [Float] Seconds elapsed since start
      def elapsed_seconds
        Time.now - start_time
      end

      # Get remaining bytes to process
      #
      # @return [Integer] Bytes remaining
      def remaining_bytes
        total_bytes - bytes_done
      end

      # Get remaining files to process
      #
      # @return [Integer] Files remaining
      def remaining_files
        total_files - files_done
      end

      # Check if operation is complete
      #
      # @return [Boolean] true if all files and bytes processed
      def complete?
        files_done >= total_files && bytes_done >= total_bytes
      end

      # Get progress as hash for serialization
      #
      # @return [Hash] Progress data
      def to_h
        {
          total_files: total_files,
          total_bytes: total_bytes,
          files_done: files_done,
          bytes_done: bytes_done,
          current_file: current_file,
          percentage: percentage,
          files_percent: files_percent,
          bytes_percent: bytes_percent,
          elapsed_seconds: elapsed_seconds,
          remaining_bytes: remaining_bytes,
          remaining_files: remaining_files,
          complete: complete?
        }
      end
    end
  end
end
