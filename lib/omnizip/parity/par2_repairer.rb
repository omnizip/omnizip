# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "par2_verifier"
require_relative "reed_solomon_matrix"
require_relative "chunked_block_processor"

module Omnizip
  module Parity
    # PAR2 archive repairer
    #
    # Repairs damaged or missing files using PAR2 recovery blocks
    # and Reed-Solomon error correction.
    #
    # @example Repair damaged files
    #   repairer = Par2Repairer.new('backup.par2')
    #   result = repairer.repair
    #   puts "Repaired #{result.recovered_blocks} blocks"
    class Par2Repairer
      # Repair result
      RepairResult = Struct.new(
        :success,          # Repair successful?
        :recovered_files,  # Array of recovered file names
        :recovered_blocks, # Number of blocks recovered
        :unrecoverable,    # Array of unrecoverable file names
        :error_message,    # Error message if failed
        keyword_init: true,
      ) do
        # Check if repair was successful
        #
        # @return [Boolean] true if successful
        def success?
          success
        end

        # Check if any files remain unrecoverable
        #
        # @return [Boolean] true if some files couldn't be recovered
        def has_unrecoverable?
          !unrecoverable.empty?
        end
      end

      # @return [String] Path to PAR2 index file
      attr_reader :par2_file

      # @return [Par2Verifier] Verifier instance
      attr_reader :verifier

      # @return [Proc, nil] Progress callback
      attr_reader :progress_callback

      # Initialize repairer
      #
      # @param par2_file [String] Path to .par2 index file
      # @param progress [Proc, nil] Progress callback
      # @raise [ArgumentError] if file doesn't exist
      def initialize(par2_file, progress: nil)
        raise ArgumentError, "PAR2 file not found: #{par2_file}" unless
          File.exist?(par2_file)

        @par2_file = par2_file
        @progress_callback = progress
        @verifier = Par2Verifier.new(par2_file)
      end

      # Repair damaged files
      #
      # @param output_dir [String, nil] Output directory (default: same as source)
      # @return [RepairResult] Repair results
      def repair(output_dir: nil)
        report_progress(0, "Verifying files")

        # First verify to find damage
        verification = @verifier.verify

        if verification.all_ok?
          return RepairResult.new(
            success: true,
            recovered_files: [],
            recovered_blocks: 0,
            unrecoverable: [],
            error_message: nil,
          )
        end

        unless verification.repairable?
          return RepairResult.new(
            success: false,
            recovered_files: [],
            recovered_blocks: 0,
            unrecoverable: verification.damaged_files + verification.missing_files,
            error_message: "Insufficient recovery blocks to repair damage",
          )
        end

        report_progress(10, "Loading recovery blocks")

        # Load all data
        data_blocks = load_data_blocks(verification)
        parity_blocks_by_exp = load_parity_blocks_by_exponent

        report_progress(30, "Calculating repairs")

        # Identify erasures (damaged/missing blocks)
        erasures = identify_erasures(verification)

        report_progress(50, "Recovering damaged blocks")

        # Perform Reed-Solomon decoding with new decoder
        begin
          recovered_data = perform_recovery(
            data_blocks,
            parity_blocks_by_exp,
            erasures,
            @verifier.metadata[:block_size],
          )
        rescue StandardError => e
          return RepairResult.new(
            success: false,
            recovered_files: [],
            recovered_blocks: 0,
            unrecoverable: verification.damaged_files,
            error_message: "Recovery failed: #{e.message}",
          )
        end

        # Combine original good blocks with recovered blocks
        recovered_blocks = data_blocks.each_with_index.map do |block, idx|
          if erasures.include?(idx)
            recovered_data[idx]
          else
            block
          end
        end

        report_progress(80, "Writing repaired files")

        # Write recovered files
        recovered_files = write_recovered_files(
          recovered_blocks,
          erasures,
          output_dir,
        )

        report_progress(100, "Repair complete")

        RepairResult.new(
          success: true,
          recovered_files: recovered_files,
          recovered_blocks: erasures.size,
          unrecoverable: [],
          error_message: nil,
        )
      end

      private

      # Load all data blocks from files
      #
      # @param verification [VerificationResult] Verification results
      # @return [Array<String, nil>] Data blocks (nil for missing)
      def load_data_blocks(verification)
        blocks = []
        block_size = @verifier.metadata[:block_size]

        file_list = @verifier.instance_variable_get(:@file_list)

        # Get list of damaged/missing files from verification
        damaged_files = verification.damaged_files
        missing_files = verification.missing_files

        block_index = 0

        file_list.each_with_index do |file_info, _file_idx|
          file_path = @verifier.send(:find_file_path, file_info[:filename])
          (file_info[:size].to_f / block_size).ceil

          # Treat damaged files same as missing files - don't read corrupted data
          if damaged_files.include?(file_info[:filename]) || missing_files.include?(file_info[:filename])
            # File is damaged or missing - use nil blocks for recovery
            num_blocks = (file_info[:size].to_f / block_size).ceil
            blocks.concat([nil] * num_blocks)
            block_index += num_blocks
          elsif file_path && File.exist?(file_path)
            # Read file blocks (only for intact files)
            blocks_read = 0
            File.open(file_path, "rb") do |io|
              while (data = io.read(block_size))
                # Pad last block
                if data.bytesize < block_size
                  data += "\x00" * (block_size - data.bytesize)
                end
                blocks << data
                block_index += 1
                blocks_read += 1
              end
            end
          else
            # File not found and not in damaged list - shouldn't happen
            num_blocks = (file_info[:size].to_f / block_size).ceil
            blocks.concat([nil] * num_blocks)
            block_index += num_blocks
          end
        end

        blocks
      end

      # Load parity blocks indexed by exponent
      #
      # Returns unique recovery blocks sorted by exponent.
      # Multiple blocks with same exponent are consolidated.
      #
      # @return [Hash] Map of exponent => recovery_block_data
      def load_parity_blocks_by_exponent
        recovery_blocks = @verifier.instance_variable_get(:@recovery_blocks)

        # Group by exponent and take first block for each
        # (PAR2 can have multiple slices with same exponent for large data)
        blocks_by_exp = {}
        recovery_blocks.each do |rb|
          exp = rb[:exponent]
          blocks_by_exp[exp] ||= rb[:data]
        end

        blocks_by_exp
      end

      # Identify erasure locations
      #
      # @param verification [VerificationResult] Verification results
      # @return [Array<Integer>] Block indices that need recovery
      def identify_erasures(verification)
        erasures = []

        # Build file-to-blocks mapping using verifier's file list
        # Note: @verifier was populated by the verify() call in repair()
        file_list = @verifier.instance_variable_get(:@file_list)
        block_size = @verifier.metadata[:block_size]

        # Ensure metadata is loaded
        if file_list.nil? || file_list.empty?
          raise "Internal error: file_list not populated in verifier"
        end

        block_idx = 0
        file_blocks_map = {}
        file_list.each do |file_info|
          num_blocks = (file_info[:size].to_f / block_size).ceil
          file_blocks_map[file_info[:filename]] =
            (block_idx...(block_idx + num_blocks)).to_a
          block_idx += num_blocks
        end

        # Add ALL blocks from damaged files
        verification.damaged_files.each do |filename|
          if file_blocks_map[filename]
            erasures.concat(file_blocks_map[filename])
          end
        end

        # Add ALL blocks from missing files
        verification.missing_files.each do |filename|
          if file_blocks_map[filename]
            erasures.concat(file_blocks_map[filename])
          end
        end

        erasures.sort.uniq
      end

      # Write recovered files to disk
      #
      # @param recovered_blocks [Array<String>] Complete set of data blocks (recovered + original)
      # @param erasures [Array<Integer>] Block indices that were recovered
      # @param output_dir [String, nil] Output directory
      # @return [Array<String>] Recovered file names
      def write_recovered_files(recovered_blocks, erasures, output_dir)
        recovered_files = []
        block_idx = 0

        output_dir ||= File.dirname(@par2_file)
        FileUtils.mkdir_p(output_dir)

        @verifier.instance_variable_get(:@file_list).each do |file_info|
          num_blocks = (file_info[:size].to_f / @verifier.metadata[:block_size]).ceil
          file_blocks_range = (block_idx...(block_idx + num_blocks)).to_a

          # Check if any blocks from this file were in the erasure list (damaged/missing)
          damaged_blocks = file_blocks_range & erasures
          if damaged_blocks.any?
            output_path = File.join(output_dir, file_info[:filename])

            # Extract blocks for this file from the complete recovered set
            # recovered_blocks contains ALL blocks (both original and recovered)
            file_blocks = recovered_blocks[block_idx, num_blocks]

            # Only write if we have blocks to write
            if file_blocks && !file_blocks.empty? && file_blocks.all?
              write_recovered_file(
                output_path,
                file_blocks,
                file_info[:size],
              )
              recovered_files << file_info[:filename]
            end
          end

          block_idx += num_blocks
        end

        recovered_files
      end

      # Write single recovered file
      #
      # @param output_path [String] Output file path
      # @param blocks [Array<String>] File blocks
      # @param file_size [Integer] Original file size
      def write_recovered_file(output_path, blocks, file_size)
        FileUtils.mkdir_p(File.dirname(output_path))

        File.open(output_path, "wb") do |io|
          blocks.each do |block|
            io.write(block)
          end

          # Truncate to exact size (remove padding)
          io.truncate(file_size)
        end
      end

      # Perform Reed-Solomon recovery using chunked processing
      #
      # Implements par2cmdline's incremental approach:
      # 1. Compute matrix coefficients once
      # 2. Process data in chunks (memory-efficient)
      # 3. Incrementally build recovered blocks
      #
      # @param data_blocks [Array<String, nil>] Data blocks (nil for missing/damaged)
      # @param parity_blocks_by_exp [Hash] Map of exponent => parity_block
      # @param erasures [Array<Integer>] Block indices to recover
      # @param block_size [Integer] Block size in bytes
      # @return [Hash<Integer, String>] Map of block_index => recovered_block
      def perform_recovery(data_blocks, parity_blocks_by_exp, erasures,
block_size)
        # Build present_blocks hash (only non-erased, non-nil blocks)
        present_blocks = {}
        data_blocks.each_with_index do |block, idx|
          unless erasures.include?(idx) || block.nil?
            present_blocks[idx] =
              block
          end
        end

        # Build recovery_blocks hash (exponent => data)
        recovery_blocks = {}
        parity_blocks_by_exp.sort.each do |exponent, data|
          recovery_blocks[exponent] = data
        end

        # Determine which recovery exponents to use (first N where N = missing count)
        recovery_exponents = recovery_blocks.keys.sort.take(erasures.size)

        # Build and compute RS matrix
        matrix = ReedSolomonMatrix.new(
          present_blocks.keys.sort,
          erasures.sort,
          recovery_exponents,
          data_blocks.size, # total_inputs
          block_size,
        )

        # Compute matrix coefficients (Gaussian elimination - done once)
        matrix.compute!

        # Select only the recovery blocks we're using
        used_recovery_blocks = {}
        recovery_exponents.each do |exp|
          used_recovery_blocks[exp] = recovery_blocks[exp]
        end

        # Process blocks incrementally using chunked processor
        processor = ChunkedBlockProcessor.new(
          matrix,
          present_blocks,
          used_recovery_blocks,
          erasures.sort,
          block_size,
        )

        # Returns hash of recovered blocks
        processor.process_all
      end

      # Report progress if callback provided
      #
      # @param percent [Integer] Completion percentage
      # @param message [String] Progress message
      def report_progress(percent, message)
        @progress_callback&.call(percent, message)
      end
    end
  end
end
