# frozen_string_literal: true

require "digest"
require_relative "par2_creator"

module Omnizip
  module Parity
    # PAR2 archive verifier
    #
    # Verifies file integrity using PAR2 recovery files and checks
    # if damaged files can be repaired.
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
        keyword_init: true
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
      end

      # Verify files against PAR2 data
      #
      # @return [VerificationResult] Verification results
      def verify
        parse_par2_file

        damaged_files = []
        damaged_blocks = []
        missing_files = []

        # Check each file
        @file_list.each do |file_info|
          file_path = find_file_path(file_info[:filename])

          if file_path.nil?
            missing_files << file_info[:filename]
            next
          end

          # Verify file integrity
          damage = verify_file(file_path, file_info)
          if damage[:damaged]
            damaged_files << file_info[:filename]
            damaged_blocks.concat(damage[:blocks])
          end
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
          recovery_blocks: @recovery_blocks.size
        )
      end

      private

      # Parse PAR2 index file
      def parse_par2_file
        File.open(@par2_file, "rb") do |io|
          while !io.eof?
            packet = read_packet(io)
            break unless packet

            process_packet(packet)
          end
        end

        # Load recovery blocks from volume files
        load_recovery_volumes
      end

      # Read packet from PAR2 file
      #
      # @param io [IO] Input IO
      # @return [Hash, nil] Packet data or nil if EOF
      def read_packet(io)
        # Read packet header
        magic = io.read(8)
        return nil unless magic == Par2Creator::PACKET_SIGNATURE

        length = io.read(8).unpack1("Q<")
        packet_hash = io.read(16)
        set_id = io.read(16)
        packet_type = io.read(16)

        # Read packet data
        data_length = length - 64
        packet_data = io.read(data_length)

        {
          magic: magic,
          length: length,
          hash: packet_hash,
          set_id: set_id,
          type: packet_type,
          data: packet_data
        }
      end

      # Process parsed packet
      #
      # @param packet [Hash] Packet data
      def process_packet(packet)
        case packet[:type]
        when Par2Creator::PACKET_TYPE_MAIN
          process_main_packet(packet[:data])
        when Par2Creator::PACKET_TYPE_FILE_DESC
          process_file_desc_packet(packet[:data])
        when Par2Creator::PACKET_TYPE_IFSC
          # Input File Slice Checksum packets are used during verification
          # but we don't need to store them for basic verification
        when Par2Creator::PACKET_TYPE_RECOVERY
          # Recovery packets are in volume files
        end
      end

      # Process main packet
      #
      # @param data [String] Packet data
      def process_main_packet(data)
        pos = 0
        @metadata[:set_id] = data[pos, 16]
        pos += 16

        @metadata[:block_size] = data[pos, 8].unpack1("Q<")
        pos += 8

        @metadata[:recovery_file_count] = data[pos, 8].unpack1("Q<")
        pos += 8

        @metadata[:file_count] = data[pos, 8].unpack1("Q<")
      end

      # Process file description packet
      #
      # @param data [String] Packet data
      def process_file_desc_packet(data)
        pos = 0
        file_id = data[pos, 16]
        pos += 16

        hash_full = data[pos, 16]
        pos += 16

        hash_16k = data[pos, 16]
        pos += 16

        file_size = data[pos, 8].unpack1("Q<")
        pos += 8

        # Read filename (null-terminated)
        filename = data[pos..-1].unpack1("Z*")

        @file_list << {
          file_id: file_id,
          hash_full: hash_full,
          hash_16k: hash_16k,
          size: file_size,
          filename: filename
        }
      end

      # Load recovery blocks from volume files
      def load_recovery_volumes
        base_name = File.basename(@par2_file, ".par2")
        dir_name = File.dirname(@par2_file)

        # Find all volume files
        pattern = File.join(dir_name, "#{base_name}.vol*.par2")
        volume_files = Dir.glob(pattern).sort

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
            packet = read_packet(io)
            break unless packet

            if packet[:type] == Par2Creator::PACKET_TYPE_RECOVERY
              process_recovery_packet(packet[:data])
            end
          end
        end
      end

      # Process recovery packet
      #
      # @param data [String] Packet data
      def process_recovery_packet(data)
        exponent = data[0, 4].unpack1("L<")
        block_data = data[4..-1]

        @recovery_blocks << {
          exponent: exponent,
          data: block_data
        }
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
            return { damaged: true, blocks: [], size_mismatch: true }
          end

          # Quick check: first 16KB hash
          first_16k = io.read(16384) || ""
          hash_16k = Digest::MD5.digest(first_16k)
          if hash_16k != file_info[:hash_16k]
            damaged = true
          end

          # Full check: complete file hash
          io.rewind
          hash_full = Digest::MD5.file(file_path).digest
          if hash_full != file_info[:hash_full]
            damaged = true

            # Identify damaged blocks
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

        io.rewind
        while (data = io.read(@metadata[:block_size]))
          # Pad last block
          if data.bytesize < @metadata[:block_size]
            data += "\x00" * (@metadata[:block_size] - data.bytesize)
          end

          # Check block hash
          block_hash = Digest::MD5.digest(data)
          # Note: Would need to store block hashes from IFSC packets
          # For now, mark as potentially damaged

          damaged << block_idx
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