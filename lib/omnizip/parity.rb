# frozen_string_literal: true

module Omnizip
  # PAR2 parity archive support
  #
  # Provides creation, verification, and repair of PAR2 parity files
  # for protecting archives and data files against corruption.
  #
  # PAR2 uses Reed-Solomon error correction codes to create recovery
  # data that can reconstruct missing or corrupted blocks.
  #
  # @example Create PAR2 protection
  #   Omnizip::Parity.create('archive.zip', redundancy: 10)
  #
  # @example Verify and repair
  #   result = Omnizip::Parity.verify('archive.par2')
  #   Omnizip::Parity.repair('archive.par2') if result.repairable?
  module Parity
    autoload :Par2cmdlineCoefficients, "omnizip/parity/par2cmdline_coefficients"
    autoload :Par2Creator, "omnizip/parity/par2_creator"
    autoload :Par2Verifier, "omnizip/parity/par2_verifier"
    autoload :Par2Repairer, "omnizip/parity/par2_repairer"

    class << self
      # Create PAR2 recovery files for archive or files
      #
      # @param file_or_pattern [String] File path or glob pattern
      # @param redundancy [Integer] Redundancy percentage (0-100)
      # @param block_size [Integer] Block size in bytes
      # @param output_dir [String, nil] Output directory for PAR2 files
      # @param progress [Proc, nil] Progress callback
      # @return [Array<String>] Created PAR2 file paths
      #
      # @example Create with 10% redundancy
      #   Omnizip::Parity.create('backup.7z', redundancy: 10)
      #
      # @example Create for multiple files
      #   Omnizip::Parity.create('data/*.dat', redundancy: 5)
      #
      # @example With progress tracking
      #   Omnizip::Parity.create('large.zip',
      #     redundancy: 10,
      #     progress: ->(pct, msg) { puts "#{pct}%: #{msg}" }
      #   )
      def create(file_or_pattern, redundancy: 5, block_size: Par2Creator::DEFAULT_BLOCK_SIZE,
                 output_dir: nil, progress: nil)
        # Try glob expansion first (handles both patterns and single files)
        files = Dir.glob(file_or_pattern)

        # If glob returns nothing, check if it's a single existing file
        if files.empty? && File.exist?(file_or_pattern) && !File.directory?(file_or_pattern)
          files = [file_or_pattern]
        end

        if files.empty?
          raise ArgumentError,
                "No files match pattern: #{file_or_pattern}"
        end

        # Create PAR2 creator
        creator = Par2Creator.new(
          redundancy: redundancy,
          block_size: block_size,
          progress: progress,
        )

        # Add all files
        files.each { |file| creator.add_file(file) }

        # Determine output base name
        dir = output_dir || File.dirname(files.first)
        base_name = if files.size == 1
                      # Use file's directory and base name without extension
                      File.join(dir, File.basename(files.first, ".*"))
                    else
                      # Use files' directory name for multiple files
                      File.join(dir,
                                File.basename(File.dirname(files.first)))
                    end

        # Create PAR2 files
        creator.create(base_name)
      end

      # Verify files using PAR2 recovery data
      #
      # @param par2_file [String] Path to .par2 index file
      # @return [Par2Verifier::VerificationResult] Verification results
      #
      # @example Verify archive integrity
      #   result = Omnizip::Parity.verify('backup.par2')
      #   if result.all_ok?
      #     puts "All files intact"
      #   elsif result.repairable?
      #     puts "Damage detected but repairable"
      #   else
      #     puts "Damage cannot be repaired"
      #   end
      def verify(par2_file)
        verifier = Par2Verifier.new(par2_file)
        verifier.verify
      end

      # Repair damaged files using PAR2 recovery data
      #
      # @param par2_file [String] Path to .par2 index file
      # @param output_dir [String, nil] Output directory for repaired files
      # @param progress [Proc, nil] Progress callback
      # @return [Par2Repairer::RepairResult] Repair results
      #
      # @example Repair damaged archive
      #   result = Omnizip::Parity.repair('backup.par2')
      #   if result.success?
      #     puts "Successfully recovered #{result.recovered_files.join(', ')}"
      #   else
      #     puts "Repair failed: #{result.error_message}"
      #   end
      def repair(par2_file, output_dir: nil, progress: nil)
        repairer = Par2Repairer.new(par2_file, progress: progress)
        repairer.repair(output_dir: output_dir)
      end

      # Quick check if PAR2 files exist for a file
      #
      # @param file_path [String] Path to protected file
      # @return [Boolean] true if PAR2 files exist
      #
      # @example Check for protection
      #   if Omnizip::Parity.protected?('backup.zip')
      #     puts "File is protected by PAR2"
      #   end
      def protected?(file_path)
        base_name = File.basename(file_path, ".*")
        dir_name = File.dirname(file_path)
        par2_file = File.join(dir_name, "#{base_name}.par2")

        File.exist?(par2_file)
      end

      # Get PAR2 protection information
      #
      # @param file_path [String] Path to protected file
      # @return [Hash, nil] Protection information or nil if not protected
      #
      # @example Get protection info
      #   info = Omnizip::Parity.info('backup.zip')
      #   puts "Redundancy: #{info[:redundancy]}%"
      #   puts "Block size: #{info[:block_size]} bytes"
      def info(file_path)
        base_name = File.basename(file_path, ".*")
        dir_name = File.dirname(file_path)
        par2_file = File.join(dir_name, "#{base_name}.par2")

        return nil unless File.exist?(par2_file)

        verifier = Par2Verifier.new(par2_file)
        verifier.send(:parse_par2_file)

        total_blocks = verifier.send(:calculate_total_blocks)
        recovery_blocks = verifier.instance_variable_get(:@recovery_blocks).size

        {
          par2_file: par2_file,
          block_size: verifier.metadata[:block_size],
          total_blocks: total_blocks,
          file_count: verifier.metadata[:file_count] || verifier.instance_variable_get(:@file_list).size,
          recovery_blocks: recovery_blocks,
          redundancy: calculate_redundancy(total_blocks, recovery_blocks),
        }
      end

      private

      # Calculate redundancy percentage
      #
      # @param total_blocks [Integer] Total data blocks
      # @param recovery_blocks [Integer] Recovery blocks
      # @return [Float] Redundancy percentage
      def calculate_redundancy(total_blocks, recovery_blocks)
        return 0.0 if total_blocks.nil? || total_blocks.zero?

        (recovery_blocks.to_f / total_blocks * 100).round(2)
      end
    end
  end
end
