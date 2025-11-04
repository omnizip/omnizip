# frozen_string_literal: true

module Omnizip
  module Commands
    # Archive verification command
    class ArchiveVerifyCommand
      attr_reader :options

      # Initialize command
      #
      # @param options [Hash] Command options
      def initialize(options = {})
        @options = options
      end

      # Run verification
      #
      # @param archive_path [String] Path to archive
      def run(archive_path)
        require_relative "../formats/rar"

        unless File.exist?(archive_path)
          raise "Archive not found: #{archive_path}"
        end

        # Detect format
        format = detect_format(archive_path)

        case format
        when :rar
          verify_rar(archive_path)
        else
          puts "Verification not supported for #{format} archives"
          exit 1
        end
      end

      private

      # Detect archive format
      #
      # @param path [String] Archive path
      # @return [Symbol] Format (:rar, :zip, :7z)
      def detect_format(path)
        ext = File.extname(path).downcase
        case ext
        when ".rar", ".r00", ".r01"
          :rar
        when ".zip"
          :zip
        when ".7z"
          :seven_zip
        else
          :unknown
        end
      end

      # Verify RAR archive
      #
      # @param archive_path [String] Path to RAR archive
      def verify_rar(archive_path)
        puts "Verifying #{archive_path}..." if @options[:verbose]

        result = Omnizip::Formats::Rar.verify(
          archive_path,
          use_recovery: !@options[:no_recovery]
        )

        display_verification_result(archive_path, result)

        exit 1 unless result.valid?
      end

      # Display verification results
      #
      # @param archive_path [String] Archive path
      # @param result [ArchiveVerifier::VerificationResult] Results
      def display_verification_result(archive_path, result)
        puts "\nArchive: #{archive_path}"
        puts "Format: RAR"

        if result.recovery_available
          puts "Recovery records: Yes"
        else
          puts "Recovery records: No"
        end

        puts "\nFiles:"
        puts "  Total: #{result.files_total}"
        puts "  OK: #{result.files_ok}"
        puts "  Corrupted: #{result.files_corrupted}"

        if result.files_corrupted.positive?
          puts "\nCorrupted files:"
          result.corrupted_files.each do |filename|
            puts "  - #{filename}"
          end

          if result.can_repair?
            puts "\nCan repair: Yes (using recovery records)"
          else
            puts "\nCan repair: No"
          end
        end

        if @options[:verbose] && result.errors.any?
          puts "\nErrors:"
          result.errors.each do |error|
            puts "  - #{error}"
          end
        end

        puts "\n#{result.summary}"
      end
    end
  end
end
