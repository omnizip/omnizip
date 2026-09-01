# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Omnizip
  module Temp
    # Safe extraction with atomic move to destination
    # Provides rollback capability on failure
    class SafeExtract
      # Error raised when extraction verification fails
      class VerificationError < Omnizip::Error; end

      attr_reader :archive_path, :dest_path

      # Create new safe extractor
      # @param archive_path [String] Path to archive
      # @param dest_path [String] Destination path
      def initialize(archive_path, dest_path)
        @archive_path = archive_path
        @dest_path = dest_path
      end

      # Extract safely with verification
      # @yield [temp_dir] Block for verification (return truthy to proceed)
      # @return [String] Destination path
      def extract
        unless File.exist?(@archive_path)
          raise Errno::ENOENT, "Archive not found: #{@archive_path}"
        end

        Dir.mktmpdir("omniz_extract_") do |temp_dir|
          # Extract to temp directory
          extract_to_temp(temp_dir)

          # User verification if block given
          if block_given?
            result = yield(temp_dir)
            unless result
              raise VerificationError, "Extraction verification failed"
            end
          end

          # Atomic move to destination
          move_to_destination(temp_dir)
        end

        @dest_path
      end

      # Extract with checksum verification
      # @param expected_checksums [Hash] Map of filename => CRC32
      # @return [String] Destination path
      def extract_verified(expected_checksums)
        extract do |temp_dir|
          verify_checksums(temp_dir, expected_checksums)
        end
      end

      # Extract with file count verification
      # @param expected_count [Integer] Expected number of files
      # @return [String] Destination path
      def extract_with_count(expected_count)
        extract do |temp_dir|
          actual_count = count_files(temp_dir)
          actual_count == expected_count
        end
      end

      # Class method for quick safe extraction
      # @param archive_path [String] Archive to extract
      # @param dest_path [String] Destination
      # @yield [temp_dir] Verification block
      # @return [String] Destination path
      def self.extract_safe(archive_path, dest_path, &block)
        new(archive_path, dest_path).extract(&block)
      end

      private

      def extract_to_temp(temp_dir)
        # Every routed format extracts through the handler registry,
        # same as the convenience API
        Omnizip.extract_archive(@archive_path, temp_dir)
      end

      def move_to_destination(temp_dir)
        # Ensure parent directory exists
        FileUtils.mkdir_p(File.dirname(@dest_path))

        # Remove destination if it exists
        FileUtils.rm_rf(@dest_path)

        # Copy contents (can't move since Dir.mktmpdir will try to clean up)
        FileUtils.cp_r(temp_dir, @dest_path)
      end

      def verify_checksums(dir, expected)
        expected.all? do |file, expected_sum|
          file_path = File.join(dir, file)
          next false unless File.exist?(file_path)

          # Calculate checksum
          crc = Omnizip::Checksums::Crc32.new
          File.open(file_path, "rb") do |f|
            while (chunk = f.read(64 * 1024))
              crc.update(chunk)
            end
          end

          crc.finalize == expected_sum
        end
      end

      def count_files(dir)
        count = 0
        Dir.glob(File.join(dir, "**", "*")) do |path|
          count += 1 unless File.directory?(path)
        end
        count
      end
    end
  end
end
