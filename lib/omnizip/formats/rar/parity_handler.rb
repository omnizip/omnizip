# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # RAR parity operations handler
      # Reads parity data and performs recovery calculations
      class ParityHandler
        attr_reader :recovery_record, :parity_blocks

        # Initialize parity handler
        #
        # @param recovery_record [RecoveryRecord] Recovery record instance
        def initialize(recovery_record)
          @recovery_record = recovery_record
          @parity_blocks = []
        end

        # Load parity data from .rev files
        #
        # @param rev_files [Array<String>] Paths to .rev files
        # @return [Boolean] true if loaded successfully
        def load_parity_data(rev_files)
          @parity_blocks = []

          rev_files.each do |rev_file|
            blocks = parse_rev_file(rev_file)
            @parity_blocks.concat(blocks) if blocks
          end

          @parity_blocks.any?
        end

        # Verify archive blocks using parity
        #
        # @param archive_path [String] Path to archive
        # @param block_indices [Array<Integer>] Blocks to verify
        # @return [Hash] Verification results
        def verify_blocks(archive_path, block_indices = nil)
          if @parity_blocks.empty?
            return { verified: false,
                     error: "No parity data" }
          end

          blocks_to_check = block_indices || (0...total_blocks).to_a
          corrupted_blocks = []

          blocks_to_check.each do |index|
            corrupted_blocks << index unless verify_block(archive_path, index)
          end

          {
            verified: corrupted_blocks.empty?,
            total: blocks_to_check.size,
            ok: blocks_to_check.size - corrupted_blocks.size,
            corrupted: corrupted_blocks,
          }
        end

        # Calculate parity for a block
        #
        # @param data [String] Binary data
        # @param block_index [Integer] Block index
        # @return [String] Parity data
        def calculate_parity(data, block_index)
          # Basic XOR parity for simple recovery
          # In production, would use Reed-Solomon
          parity = data.bytes.reduce(0) { |acc, byte| acc ^ byte }
          [parity, block_index].pack("CN")
        end

        # Recover corrupted block
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block to recover
        # @return [String, nil] Recovered data or nil
        def recover_block(archive_path, block_index)
          return nil unless can_recover?(block_index)

          if @recovery_record.version == 5
            recover_rar5_block(archive_path, block_index)
          else
            recover_rar4_block(archive_path, block_index)
          end
        end

        # Check if block can be recovered
        #
        # @param block_index [Integer] Block index
        # @return [Boolean] true if recoverable
        def can_recover?(block_index)
          return false if @parity_blocks.empty?

          # Can recover if we have parity data for this block
          @parity_blocks.any? { |p| p[:index] == block_index }
        end

        # Get total number of blocks
        #
        # @return [Integer] Total blocks
        def total_blocks
          return 0 if @recovery_record.block_size.zero?

          (@recovery_record.protected_size / @recovery_record.block_size.to_f).ceil
        end

        # Get parity block by index
        #
        # @param index [Integer] Block index
        # @return [Hash, nil] Parity block data
        def parity_block(index)
          @parity_blocks.find { |p| p[:index] == index }
        end

        private

        # Parse .rev file
        #
        # @param rev_file [String] Path to .rev file
        # @return [Array<Hash>, nil] Parity blocks
        def parse_rev_file(rev_file)
          return nil unless File.exist?(rev_file)

          blocks = []

          File.open(rev_file, "rb") do |io|
            # Check RAR signature in .rev file
            signature = io.read(7)
            return nil unless valid_rev_signature?(signature)

            # Parse recovery blocks
            until io.eof?
              block = parse_parity_block(io)
              break unless block

              blocks << block
            end
          end

          blocks
        rescue StandardError
          nil
        end

        # Check if valid .rev file signature
        #
        # @param signature [String] File signature
        # @return [Boolean] true if valid
        def valid_rev_signature?(signature)
          return false unless signature

          bytes = signature.bytes
          bytes[0..3] == [0x52, 0x61, 0x72, 0x21] # "Rar!"
        end

        # Parse parity block from .rev file
        #
        # @param io [IO] Input stream
        # @return [Hash, nil] Parity block data
        def parse_parity_block(io)
          # Read block header
          block_size = io.read(4)&.unpack1("V")
          return nil unless block_size

          block_index = io.read(4)&.unpack1("V")
          checksum = io.read(4)&.unpack1("V")

          # Read parity data
          parity_data = io.read(block_size - 12)
          return nil unless parity_data

          {
            index: block_index,
            size: block_size,
            checksum: checksum,
            data: parity_data,
          }
        rescue StandardError
          nil
        end

        # Verify single block
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block index
        # @return [Boolean] true if block is valid
        def verify_block(archive_path, block_index)
          parity = parity_block(block_index)
          return true unless parity # No parity, assume OK

          # Read block from archive
          block_data = read_archive_block(archive_path, block_index)
          return false unless block_data

          # Calculate checksum
          calculated = calculate_block_checksum(block_data)
          calculated == parity[:checksum]
        end

        # Read block from archive
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block index
        # @return [String, nil] Block data
        def read_archive_block(archive_path, block_index)
          return nil unless File.exist?(archive_path)

          block_size = @recovery_record.block_size
          offset = block_index * block_size

          File.open(archive_path, "rb") do |io|
            io.seek(offset)
            io.read(block_size)
          end
        rescue StandardError
          nil
        end

        # Calculate block checksum
        #
        # @param data [String] Block data
        # @return [Integer] CRC32 checksum
        def calculate_block_checksum(data)
          Zlib.crc32(data)
        end

        # Recover RAR5 block using Reed-Solomon
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block index
        # @return [String, nil] Recovered data
        def recover_rar5_block(archive_path, block_index)
          parity = parity_block(block_index)
          return nil unless parity

          # Read corrupted block
          block_data = read_archive_block(archive_path, block_index)
          return nil unless block_data

          # Use Reed-Solomon decoding
          # This is a placeholder - real implementation would use
          # reed-solomon gem or similar
          recover_with_reed_solomon(block_data, parity[:data])
        end

        # Recover RAR4 block using old recovery method
        #
        # @param archive_path [String] Path to archive
        # @param block_index [Integer] Block index
        # @return [String, nil] Recovered data
        def recover_rar4_block(archive_path, block_index)
          parity = parity_block(block_index)
          return nil unless parity

          # Read corrupted block
          block_data = read_archive_block(archive_path, block_index)
          return nil unless block_data

          # Simple XOR recovery for RAR4
          recover_with_xor(block_data, parity[:data])
        end

        # Recover data using Reed-Solomon (RAR5)
        #
        # @param corrupted_data [String] Corrupted block
        # @param parity_data [String] Parity information
        # @return [String, nil] Recovered data
        def recover_with_reed_solomon(_corrupted_data, _parity_data)
          # Placeholder for Reed-Solomon recovery
          # Real implementation would use reed-solomon gem
          # For now, return nil to indicate recovery not available
          nil
        end

        # Recover data using XOR (RAR4)
        #
        # @param corrupted_data [String] Corrupted block
        # @param parity_data [String] Parity information
        # @return [String] Recovered data
        def recover_with_xor(corrupted_data, parity_data)
          # Simple XOR recovery
          result = corrupted_data.bytes.map.with_index do |byte, i|
            parity_byte = parity_data.bytes[i % parity_data.size]
            byte ^ parity_byte
          end

          result.pack("C*")
        end
      end
    end
  end
end
