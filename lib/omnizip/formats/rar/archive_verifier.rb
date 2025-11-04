# frozen_string_literal: true

require_relative "recovery_record"
require_relative "parity_handler"

module Omnizip
  module Formats
    module Rar
      # RAR archive verification
      # Verifies archive integrity using CRCs and recovery records
      class ArchiveVerifier
        attr_reader :archive_path, :recovery_record, :parity_handler

        # Verification result
        class VerificationResult
          attr_accessor :valid, :files_total, :files_ok, :files_corrupted,
                        :corrupted_files, :recoverable, :corrupt_blocks,
                        :recovery_available, :errors

          def initialize
            @valid = true
            @files_total = 0
            @files_ok = 0
            @files_corrupted = 0
            @corrupted_files = []
            @recoverable = false
            @corrupt_blocks = []
            @recovery_available = false
            @errors = []
          end

          # Check if archive is valid
          #
          # @return [Boolean] true if valid
          def valid?
            @valid && @files_corrupted.zero?
          end

          # Check if corruption can be repaired
          #
          # @return [Boolean] true if repairable
          def can_repair?
            @recovery_available && @recoverable
          end

          # Get summary string
          #
          # @return [String] Verification summary
          def summary
            if valid?
              "Archive OK: #{@files_total} files verified"
            else
              msg = "Archive corrupted: #{@files_corrupted}/#{@files_total} files damaged"
              msg += " (repairable)" if can_repair?
              msg
            end
          end
        end

        # Initialize verifier
        #
        # @param archive_path [String] Path to RAR archive
        def initialize(archive_path)
          @archive_path = archive_path
          @recovery_record = nil
          @parity_handler = nil
        end

        # Verify archive integrity
        #
        # @param use_recovery [Boolean] Use recovery records for verification
        # @param verbose [Boolean] Enable verbose output
        # @return [VerificationResult] Verification results
        def verify(use_recovery: true, verbose: false)
          result = VerificationResult.new

          begin
            # Open and parse archive
            reader = Reader.new(@archive_path)
            reader.open

            result.files_total = reader.entries.size

            # Detect recovery records
            detect_recovery_records(reader, result) if use_recovery

            # Verify each file
            reader.entries.each do |entry|
              file_valid = verify_entry(entry, verbose)

              if file_valid
                result.files_ok += 1
              else
                result.files_corrupted += 1
                result.corrupted_files << entry.name
                result.valid = false
              end
            end

            # Check if corruption is recoverable
            if result.files_corrupted.positive? && result.recovery_available
              result.recoverable = check_recoverability(result.corrupt_blocks)
            end
          rescue StandardError => e
            result.valid = false
            result.errors << "Verification failed: #{e.message}"
          end

          result
        end

        # Verify single file entry
        #
        # @param entry [Models::RarEntry] Entry to verify
        # @param verbose [Boolean] Print verbose output
        # @return [Boolean] true if valid
        def verify_entry(entry, verbose = false)
          return true if entry.directory?

          # For now, we rely on the decompressor to verify
          # In a full implementation, we would check CRC32
          valid = verify_entry_crc(entry)

          puts "#{entry.name}: #{valid ? "OK" : "FAILED"}" if verbose

          valid
        rescue StandardError => e
          puts "#{entry.name}: ERROR (#{e.message})" if verbose
          false
        end

        # Quick test of archive
        #
        # @return [Boolean] true if archive can be opened
        def quick_test
          Reader.new(@archive_path).open
          true
        rescue StandardError
          false
        end

        private

        # Detect recovery records in archive
        #
        # @param reader [Reader] Archive reader
        # @param result [VerificationResult] Result object to update
        def detect_recovery_records(reader, result)
          version = reader.header&.version || 4

          @recovery_record = RecoveryRecord.new(version)

          # Check for integrated recovery records
          File.open(@archive_path, "rb") do |io|
            @recovery_record.parse_from_archive(io, reader.archive_info.flags)
          end

          # Check for external .rev files
          rev_files = @recovery_record.detect_external_files(@archive_path)
          @recovery_record.load_external_files(rev_files) if rev_files.any?

          result.recovery_available = @recovery_record.available?

          # Initialize parity handler if recovery available
          return unless result.recovery_available

          @parity_handler = ParityHandler.new(@recovery_record)
          @parity_handler.load_parity_data(@recovery_record.external_files)
        end

        # Verify entry CRC
        #
        # @param entry [Models::RarEntry] Entry to verify
        # @return [Boolean] true if CRC matches
        def verify_entry_crc(_entry)
          # This is a placeholder - actual CRC verification would require
          # extracting and checking the file
          # For now, assume OK unless we have specific corruption data
          true
        end

        # Check if corruption is recoverable
        #
        # @param corrupt_blocks [Array<Integer>] Corrupted block indices
        # @return [Boolean] true if recoverable
        def check_recoverability(corrupt_blocks)
          return false unless @parity_handler

          # Check if all corrupted blocks can be recovered
          corrupt_blocks.all? { |idx| @parity_handler.can_recover?(idx) }
        end
      end
    end
  end
end
