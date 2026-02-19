# frozen_string_literal: true

require "digest"
require_relative "models/packet_registry"

module Omnizip
  module Parity
    # PAR2 archive verifier
    #
    # Verifies file integrity using PAR2 recovery files and checks
    # if damaged files can be repaired.
    #
    # Uses PacketRegistry and packet models for clean object-oriented
    # architecture.
    #
    # @example Verify files
    #   verifier = Par2Verifier.new('backup.par2')
    #   result = verifier.verify
    #   if result.repairable?
    #     puts "#{result.damaged_blocks.size} blocks damaged, can repair"
    #   end
    class Par2Verifier
      # Verification result
      VerificationResult = Struct.new(
        :all_ok,          # All files intact?
        :damaged_files,   # Array of damaged file names
        :damaged_blocks,  # Array of damaged block indices
        :missing_files,   # Array of missing file names
        :repairable,      # Can be repaired with available parity?
        :total_blocks,    # Total number of blocks
        :recovery_blocks, # Number of recovery blocks available
        keyword_init: true,
      ) do
        # Check if all files are OK
        #
        # @return [Boolean] true if no damage detected
        def all_ok?
          damaged_files.empty? && missing_files.empty?
        end

        # Check if damage can be repaired
        #
        # @return [Boolean] true if repairable
        def repairable?
          repairable
        end

        # Get total damage count
        #
        # @return [Integer] Number of damaged/missing blocks
        def damage_count
          damaged_blocks.size + missing_files.size
        end
      end

      # @return [String] Path to PAR2 index file
      attr_reader :par2_file

      # @return [Hash] Parsed PAR2 metadata
      attr_reader :metadata

      # Initialize verifier
      #
      # @param par2_file [String] Path to .par2 index file
      # @raise [ArgumentError] if file doesn't exist
      def initialize(par2_file)
        raise ArgumentError, "PAR2 file not found: #{par2_file}" unless
          File.exist?(par2_file)

        @par2_file = par2_file
        @metadata = {}
        @file_list = []
        @recovery_blocks = []
        @block_hashes = {} # Store IFSC block hashes for verification
      end

      # Verify files against PAR2 data
      #
      # @return [VerificationResult] Verification results
      def verify
        parse_par2_file

        damaged_files = []
        damaged_blocks = []
        missing_files = []

        # Track global block position as we iterate through files
        global_block_idx = 0

        # Check each file
        @file_list.each do |file_info|
          file_path = find_file_path(file_info[:filename])
          num_blocks = (file_info[:size].to_f / @metadata[:block_size]).ceil

          if file_path.nil?
            missing_files << file_info[:filename]
            global_block_idx += num_blocks
            next
          end

          # Verify file integrity
          damage = verify_file(file_path, file_info)
          if damage[:damaged]
            damaged_files << file_info[:filename]
            # Convert file-relative indices to global indices
            damage[:blocks].each do |file_relative_idx|
              damaged_blocks << (global_block_idx + file_relative_idx)
            end
          end

          global_block_idx += num_blocks
        end

        # Check if repairable
        total_damage = damaged_blocks.size + (missing_files.size * avg_blocks_per_file)
        repairable = total_damage <= @recovery_blocks.size

        VerificationResult.new(
          all_ok: damaged_files.empty? && missing_files.empty?,
          damaged_files: damaged_files,
          damaged_blocks: damaged_blocks,
          missing_files: missing_files,
          repairable: repairable,
          total_blocks: calculate_total_blocks,
          recovery_blocks: @recovery_blocks.size,
        )
      end

      private

      # Parse PAR2 index file using packet models
      def parse_par2_file
        # Reset state to prevent accumulation if called multiple times
        @metadata = {}
        @file_list = []
        @recovery_blocks = []
        @block_hashes = {}

        File.open(@par2_file, "rb") do |io|
          while !io.eof?
            packet = Models::PacketRegistry.read_packet(io)
            break unless packet

            process_packet_model(packet)
          end
        end

        # CRITICAL: Sort file_list by position in Main packet file_ids
        # The Main packet defines canonical file order for Reed-Solomon matrix
        # Do NOT sort by file_id string - that breaks recovery!
        if @metadata[:file_ids]
          file_id_order = {}
          @metadata[:file_ids].each_with_index do |fid, idx|
            file_id_order[fid] = idx
          end
          @file_list.sort_by! { |f| file_id_order[f[:file_id]] || 999 }
        end

        # Load recovery blocks from volume files
        load_recovery_volumes
      end

      # Process packet using model-based approach
      #
      # @param packet [Models::Packet] Parsed packet model
      def process_packet_model(packet)
        case packet
        when Models::MainPacket
          process_main_packet_model(packet)
        when Models::FileDescriptionPacket
          process_file_description_packet_model(packet)
        when Models::IfscPacket
          process_ifsc_packet_model(packet)
        when Models::RecoverySlicePacket
          process_recovery_packet_model(packet)
        when Models::CreatorPacket
          # Creator packets are informational only
        end
      end

      # Process main packet model
      #
      # @param packet [Models::MainPacket] Main packet
      def process_main_packet_model(packet)
        @metadata[:block_size] = packet.block_size
        @metadata[:file_ids] = packet.file_ids.dup
      end

      # Process file description packet model
      #
      # @param packet [Models::FileDescriptionPacket] File description packet
      def process_file_description_packet_model(packet)
        # Skip packets with incomplete data
        return if packet.file_id.nil? || packet.filename.nil? || packet.filename.empty?
        return if packet.file_hash.nil? || packet.length.nil?

        @file_list << {
          file_id: packet.file_id,
          hash_full: packet.file_hash,
          hash_16k: packet.file_hash_16k,
          size: packet.length,
          filename: packet.filename,
        }
      end

      # Process IFSC packet model
      #
      # Each IFSC packet contains checksums for all blocks of a file
      #
      # @param packet [Models::IfscPacket] IFSC packet
      def process_ifsc_packet_model(packet)
        # Store block hashes keyed by file_id
        # Each IFSC packet contains all hashes for one file
        @block_hashes[packet.file_id] = packet.block_hashes
      end

      # Process recovery packet model
      #
      # @param packet [Models::RecoverySlicePacket] Recovery packet
      def process_recovery_packet_model(packet)
        @recovery_blocks << {
          exponent: packet.exponent,
          data: packet.recovery_data,
        }
      end

      # Load recovery blocks from volume files
      def load_recovery_volumes
        base_name = File.basename(@par2_file, ".par2")
        dir_name = File.dirname(@par2_file)

        # Find all volume files
        pattern = File.join(dir_name, "#{base_name}.vol*.par2")
        volume_files = Dir.glob(pattern)

        volume_files.each do |volume_file|
          load_recovery_volume(volume_file)
        end
      end

      # Load recovery blocks from single volume file
      #
      # @param volume_file [String] Path to volume file
      def load_recovery_volume(volume_file)
        File.open(volume_file, "rb") do |io|
          while !io.eof?
            packet = Models::PacketRegistry.read_packet(io)
            break unless packet

            # Only process recovery packets from volume files
            process_packet_model(packet) if packet.is_a?(Models::RecoverySlicePacket)
          end
        end
      end

      # Find file path for filename
      #
      # @param filename [String] Filename from PAR2
      # @return [String, nil] Full path or nil if not found
      def find_file_path(filename)
        # Look in same directory as PAR2 file
        dir = File.dirname(@par2_file)
        candidate = File.join(dir, filename)

        return candidate if File.exist?(candidate)

        # Look in current directory
        return filename if File.exist?(filename)

        nil
      end

      # Verify single file
      #
      # @param file_path [String] Path to file
      # @param file_info [Hash] Expected file information
      # @return [Hash] Damage information
      def verify_file(file_path, file_info)
        damaged_blocks = []
        damaged = false

        File.open(file_path, "rb") do |io|
          # Quick check: file size
          if io.size != file_info[:size]
            damaged = true
            # Still identify damaged blocks even with size mismatch
            damaged_blocks = identify_damaged_blocks(io, file_info)
            return { damaged: damaged, blocks: damaged_blocks,
                     size_mismatch: true }
          end

          # Quick check: first 16KB hash
          first_16k = io.read(16384) || ""
          hash_16k = Digest::MD5.digest(first_16k)
          if hash_16k == file_info[:hash_16k]
            # Full check: complete file hash
            io.rewind
            hash_full = Digest::MD5.file(file_path).digest
            if hash_full != file_info[:hash_full]
              damaged = true
              # Identify damaged blocks
              damaged_blocks = identify_damaged_blocks(io, file_info)
            end
          else
            damaged = true
            # Identify damaged blocks when quick check fails
            damaged_blocks = identify_damaged_blocks(io, file_info)
          end
        end

        { damaged: damaged, blocks: damaged_blocks }
      end

      # Identify which blocks are damaged
      #
      # @param io [IO] File IO
      # @param file_info [Hash] File information
      # @return [Array<Integer>] Damaged block indices
      def identify_damaged_blocks(io, file_info)
        damaged = []
        block_idx = 0
        expected_hashes = @block_hashes[file_info[:file_id]] || []

        io.rewind
        while (data = io.read(@metadata[:block_size]))
          # Pad last block
          if data.bytesize < @metadata[:block_size]
            data += "\x00" * (@metadata[:block_size] - data.bytesize)
          end

          # Check block hash against stored IFSC hash
          block_hash = Digest::MD5.digest(data)
          if block_idx < expected_hashes.size && block_hash != expected_hashes[block_idx]
            damaged << block_idx
          end

          block_idx += 1
        end

        damaged
      end

      # Calculate average blocks per file
      #
      # @return [Integer] Average blocks per file
      def avg_blocks_per_file
        return 0 if @file_list.empty?

        total_size = @file_list.sum { |f| f[:size] }
        total_blocks = (total_size.to_f / @metadata[:block_size]).ceil
        (total_blocks.to_f / @file_list.size).ceil
      end

      # Calculate total blocks
      #
      # @return [Integer] Total number of blocks
      def calculate_total_blocks
        @file_list.sum do |file_info|
          (file_info[:size].to_f / @metadata[:block_size]).ceil
        end
      end
    end
  end
end
