# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "par2_verifier"
require_relative "reed_solomon"

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
        keyword_init: true
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
            error_message: nil
          )
        end

        unless verification.repairable?
          return RepairResult.new(
            success: false,
            recovered_files: [],
            recovered_blocks: 0,
            unrecoverable: verification.damaged_files + verification.missing_files,
            error_message: "Insufficient recovery blocks to repair damage"
          )
        end

        report_progress(10, "Loading recovery blocks")

        # Load all data
        data_blocks = load_data_blocks
        parity_blocks = load_parity_blocks

        report_progress(30, "Calculating repairs")

        # Identify erasures (damaged/missing blocks)
        erasures = identify_erasures(verification)

        # Perform Reed-Solomon decoding
        rs_decoder = ReedSolomon.new(block_size: @verifier.metadata[:block_size])

        report_progress(50, "Recovering damaged blocks")

        begin
          recovered_blocks = rs_decoder.decode(
            data_blocks,
            parity_blocks,
            erasures: erasures
          )
        rescue => e
          return RepairResult.new(
            success: false,
            recovered_files: [],
            recovered_blocks: 0,
            unrecoverable: verification.damaged_files,
            error_message: "Recovery failed: #{e.message}"
          )
        end

        report_progress(80, "Writing repaired files")

        # Write recovered files
        recovered_files = write_recovered_files(
          recovered_blocks,
          erasures,
          output_dir
        )

        report_progress(100, "Repair complete")

        RepairResult.new(
          success: true,
          recovered_files: recovered_files,
          recovered_blocks: erasures.size,
          unrecoverable: [],
          error_message: nil
        )
      end

      private

      # Load all data blocks from files
      #
      # @return [Array<String, nil>] Data blocks (nil for missing)
      def load_data_blocks
        blocks = []
        block_size = @verifier.metadata[:block_size]

        @verifier.instance_variable_get(:@file_list).each do |file_info|
          file_path = @verifier.send(:find_file_path, file_info[:filename])

          if file_path && File.exist?(file_path)
            # Read file blocks
            File.open(file_path, "rb") do |io|
              while (data = io.read(block_size))
                # Pad last block
                if data.bytesize < block_size
                  data += "\x00" * (block_size - data.bytesize)
                end
                blocks << data
              end
            end
          else
            # File missing, add nil blocks
            num_blocks = (file_info[:size].to_f / block_size).ceil
            blocks.concat([nil] * num_blocks)
          end
        end

        blocks
      end

      # Load parity blocks
      #
      # @return [Array<String>] Parity blocks
      def load_parity_blocks
        @verifier.instance_variable_get(:@recovery_blocks).map { |rb| rb[:data] }
      end

      # Identify erasure locations
      #
      # @param verification [VerificationResult] Verification results
      # @return [Array<Integer>] Block indices that need recovery
      def identify_erasures(verification)
        erasures = []

        # Add damaged blocks
        erasures.concat(verification.damaged_blocks)

        # Add missing file blocks
        block_idx = 0
        @verifier.instance_variable_get(:@file_list).each do |file_info|
          num_blocks = (file_info[:size].to_f / @verifier.metadata[:block_size]).ceil

          if verification.missing_files.include?(file_info[:filename])
            # All blocks from this file are missing
            erasures.concat((block_idx...(block_idx + num_blocks)).to_a)
          end

          block_idx += num_blocks
        end

        erasures.sort.uniq
      end

      # Write recovered files to disk
      #
      # @param recovered_blocks [Array<String>] Recovered block data
      # @param erasures [Array<Integer>] Recovered block indices
      # @param output_dir [String, nil] Output directory
      # @return [Array<String>] Recovered file names
      def write_recovered_files(recovered_blocks, erasures, output_dir)
        recovered_files = []
        block_idx = 0

        output_dir ||= File.dirname(@par2_file)
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

        @verifier.instance_variable_get(:@file_list).each do |file_info|
          num_blocks = (file_info[:size].to_f / @verifier.metadata[:block_size]).ceil
          file_blocks = (block_idx...(block_idx + num_blocks)).to_a

          # Check if any blocks from this file were recovered
          if (file_blocks & erasures).any?
            output_path = File.join(output_dir, file_info[:filename])
            write_recovered_file(
              output_path,
              recovered_blocks[block_idx, num_blocks],
              file_info[:size]
            )
            recovered_files << file_info[:filename]
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