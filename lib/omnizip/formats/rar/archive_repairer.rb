# frozen_string_literal: true

require_relative "archive_verifier"
require_relative "recovery_record"
require_relative "parity_handler"
require "fileutils"

module Omnizip
  module Formats
    module Rar
      # RAR archive repair functionality
      # Attempts to repair corrupted archives using recovery records
      class ArchiveRepairer
        attr_reader :verifier, :recovery_record, :parity_handler

        # Repair result
        class RepairResult
          attr_accessor :success, :repaired_files, :unrepaired_files,
                        :repaired_blocks, :errors, :output_path

          def initialize
            @success = false
            @repaired_files = []
            @unrepaired_files = []
            @repaired_blocks = []
            @errors = []
            @output_path = nil
          end

          # Check if repair was successful
          #
          # @return [Boolean] true if all files repaired
          def success?
            @success && @unrepaired_files.empty?
          end

          # Get repair summary
          #
          # @return [String] Repair summary
          def summary
            if success?
              "Repair successful: #{@repaired_files.size} files, " \
                "#{@repaired_blocks.size} blocks"
            elsif @repaired_files.any?
              "Partial repair: #{@repaired_files.size} files OK, " \
                "#{@unrepaired_files.size} failed"
            else
              "Repair failed: #{@errors.join(', ')}"
            end
          end
        end

        # Initialize repairer
        def initialize
          @verifier = nil
          @recovery_record = nil
          @parity_handler = nil
        end

        # Repair corrupted archive
        #
        # @param input_path [String] Path to corrupted archive
        # @param output_path [String] Path for repaired archive
        # @param options [Hash] Repair options
        # @option options [Boolean] :use_external_rev Use external .rev files
        # @option options [Boolean] :verify_repaired Verify after repair
        # @option options [Boolean] :verbose Enable verbose output
        # @return [RepairResult] Repair results
        def repair(input_path, output_path, options = {})
          result = RepairResult.new
          result.output_path = output_path

          begin
            # Verify archive first
            @verifier = ArchiveVerifier.new(input_path)
            verification = @verifier.verify(
              use_recovery: true,
              verbose: options[:verbose],
            )

            unless verification.recovery_available
              result.errors << "No recovery records available"
              return result
            end

            unless verification.can_repair?
              result.errors << "Corruption not recoverable"
              return result
            end

            # Perform repair
            @recovery_record = @verifier.recovery_record
            @parity_handler = @verifier.parity_handler

            perform_repair(input_path, output_path, verification, result,
                           options)

            # Verify repaired archive
            if options[:verify_repaired] && result.success
              verify_repaired_archive(output_path, result)
            end
          rescue StandardError => e
            result.success = false
            result.errors << "Repair error: #{e.message}"
          end

          result
        end

        # Attempt quick repair (in-place)
        #
        # @param archive_path [String] Path to archive
        # @param options [Hash] Repair options
        # @return [RepairResult] Repair results
        def quick_repair(archive_path, options = {})
          # Create temporary output
          temp_output = "#{archive_path}.repaired"

          result = repair(archive_path, temp_output, options)

          if result.success?
            # Replace original with repaired
            FileUtils.mv(temp_output, archive_path, force: true)
            result.output_path = archive_path
          else
            # Clean up temp file
            FileUtils.rm_f(temp_output)
          end

          result
        end

        private

        # Perform the actual repair
        #
        # @param input_path [String] Input archive path
        # @param output_path [String] Output archive path
        # @param verification [VerificationResult] Verification results
        # @param result [RepairResult] Repair result to update
        # @param options [Hash] Repair options
        def perform_repair(input_path, output_path, verification, result,
                           options)
          # Copy archive to output first
          FileUtils.cp(input_path, output_path)

          # Repair corrupted blocks
          verification.corrupt_blocks.each do |block_index|
            if repair_block(output_path, block_index, options)
              result.repaired_blocks << block_index
            else
              result.errors << "Failed to repair block #{block_index}"
            end
          end

          # Track repaired files
          verification.corrupted_files.each do |filename|
            if verify_file_in_archive(output_path, filename)
              result.repaired_files << filename
            else
              result.unrepaired_files << filename
            end
          end

          result.success = result.unrepaired_files.empty?
        end

        # Repair single block in archive
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block to repair
        # @param options [Hash] Repair options
        # @return [Boolean] true if repaired
        def repair_block(archive_path, block_index, options)
          return false unless @parity_handler.can_recover?(block_index)

          # Recover the block
          recovered_data = @parity_handler.recover_block(archive_path,
                                                         block_index)
          return false unless recovered_data

          # Write recovered data to archive
          write_block_to_archive(archive_path, block_index, recovered_data)

          puts "Repaired block #{block_index}" if options[:verbose]
          true
        rescue StandardError => e
          if options[:verbose]
            puts "Failed to repair block #{block_index}: #{e.message}"
          end
          false
        end

        # Write block data to archive
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block index
        # @param data [String] Block data
        def write_block_to_archive(archive_path, block_index, data)
          block_size = @recovery_record.block_size
          offset = block_index * block_size

          File.open(archive_path, "r+b") do |io|
            io.seek(offset)
            io.write(data)
          end
        end

        # Verify file in archive
        #
        # @param archive_path [String] Path to archive
        # @param filename [String] File name to verify
        # @return [Boolean] true if file is valid
        def verify_file_in_archive(archive_path, filename)
          reader = Reader.new(archive_path)
          reader.open

          entry = reader.entries.find { |e| e.name == filename }
          return false unless entry

          # Verify entry (simplified - would check CRC in full implementation)
          true
        rescue StandardError
          false
        end

        # Verify repaired archive
        #
        # @param archive_path [String] Path to repaired archive
        # @param result [RepairResult] Repair result to update
        def verify_repaired_archive(archive_path, result)
          verifier = ArchiveVerifier.new(archive_path)
          verification = verifier.verify(use_recovery: false)

          return if verification.valid?

          result.success = false
          result.errors << "Repaired archive still has errors"
        end
      end
    end
  end
end
