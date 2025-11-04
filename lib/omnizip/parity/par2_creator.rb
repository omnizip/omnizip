# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "reed_solomon"
require_relative "galois_field"

module Omnizip
  module Parity
    # PAR2 parity archive creator
    #
    # Creates PAR2 recovery files using Reed-Solomon error correction.
    # PAR2 files allow recovery of corrupted or missing data blocks.
    #
    # @example Create PAR2 files for an archive
    #   creator = Par2Creator.new(redundancy: 10, block_size: 16384)
    #   creator.add_file('important.zip')
    #   creator.create('important')
    #   # Creates: important.par2, important.vol00+01.par2, etc.
    #
    # @example Multiple files with custom settings
    #   creator = Par2Creator.new(
    #     redundancy: 5,
    #     block_size: 32768,
    #     progress: ->(pct) { puts "Progress: #{pct}%" }
    #   )
    #   creator.add_file('file1.dat')
    #   creator.add_file('file2.dat')
    #   creator.create('backup')
    class Par2Creator
      # PAR2 packet signature
      PACKET_SIGNATURE = "PAR2\x00PKT".b.freeze

      # Packet type identifiers
      PACKET_TYPE_MAIN = "PAR 2.0\x00Main\x00\x00\x00\x00".freeze
      PACKET_TYPE_FILE_DESC = "PAR 2.0\x00FileDesc".freeze
      PACKET_TYPE_IFSC = "PAR 2.0\x00IFSC\x00\x00\x00\x00".freeze
      PACKET_TYPE_RECOVERY = "PAR 2.0\x00RecvSlic".freeze

      # Default block size (16KB)
      DEFAULT_BLOCK_SIZE = 16384

      # @return [Integer] Block size in bytes
      attr_reader :block_size

      # @return [Integer] Redundancy percentage (0-100)
      attr_reader :redundancy

      # @return [Array<Hash>] Files to protect
      attr_reader :files

      # @return [Proc, nil] Progress callback
      attr_reader :progress_callback

      # File information structure
      FileInfo = Struct.new(
        :path,           # File path
        :file_id,        # MD5 hash of file ID
        :hash_16k,       # MD5 of first 16KB
        :hash_full,      # MD5 of full file
        :size,           # File size
        :blocks,         # Array of file blocks
        keyword_init: true
      )

      # Initialize PAR2 creator
      #
      # @param redundancy [Integer] Redundancy percentage (0-100)
      # @param block_size [Integer] Block size in bytes
      # @param progress [Proc, nil] Progress callback proc
      def initialize(redundancy: 5, block_size: DEFAULT_BLOCK_SIZE, progress: nil)
        @redundancy = validate_redundancy(redundancy)
        @block_size = validate_block_size(block_size)
        @progress_callback = progress
        @files = []
        @set_id = generate_set_id
      end

      # Add file to PAR2 set
      #
      # @param file_path [String] Path to file
      # @raise [ArgumentError] if file doesn't exist
      def add_file(file_path)
        raise ArgumentError, "File not found: #{file_path}" unless
          File.exist?(file_path)

        file_info = analyze_file(file_path)
        @files << file_info
      end

      # Create PAR2 recovery files
      #
      # @param base_name [String] Base name for PAR2 files
      # @return [Array<String>] Paths to created PAR2 files
      def create(base_name)
        validate_files!

        # Calculate total blocks and recovery blocks needed
        total_blocks = calculate_total_blocks
        recovery_blocks = calculate_recovery_blocks(total_blocks)

        report_progress(0, "Initializing PAR2 creation")

        # Create main PAR2 index file
        index_file = create_index_file(base_name)

        # Create recovery volume files
        volume_files = create_recovery_volumes(
          base_name,
          recovery_blocks,
          total_blocks
        )

        report_progress(100, "PAR2 creation complete")

        [index_file] + volume_files
      end

      private

      # Validate redundancy percentage
      #
      # @param redundancy [Integer] Redundancy value
      # @return [Integer] Validated redundancy
      def validate_redundancy(redundancy)
        unless redundancy.between?(0, 100)
          raise ArgumentError, "Redundancy must be 0-100, got #{redundancy}"
        end
        redundancy
      end

      # Validate block size
      #
      # @param block_size [Integer] Block size value
      # @return [Integer] Validated block size
      def validate_block_size(block_size)
        unless block_size.positive? && (block_size % 4).zero?
          raise ArgumentError,
                "Block size must be positive and divisible by 4, got #{block_size}"
        end
        block_size
      end

      # Validate that files have been added
      #
      # @raise [StandardError] if no files added
      def validate_files!
        raise "No files added to PAR2 set" if @files.empty?
      end

      # Generate unique set ID for this PAR2 set
      #
      # @return [String] 16-byte set ID
      def generate_set_id
        Digest::MD5.digest("#{Time.now.to_f}#{rand}")
      end

      # Analyze file and calculate hashes
      #
      # @param file_path [String] Path to file
      # @return [FileInfo] File information
      def analyze_file(file_path)
        File.open(file_path, "rb") do |io|
          file_size = io.size

          # Calculate hash of first 16KB
          first_16k = io.read(16384) || ""
          hash_16k = Digest::MD5.digest(first_16k)

          # Calculate full file hash
          io.rewind
          hash_full = Digest::MD5.file(file_path).digest

          # Generate file ID
          file_id = Digest::MD5.digest("#{File.basename(file_path)}#{file_size}")

          # Read file blocks
          io.rewind
          blocks = read_file_blocks(io)

          FileInfo.new(
            path: file_path,
            file_id: file_id,
            hash_16k: hash_16k,
            hash_full: hash_full,
            size: file_size,
            blocks: blocks
          )
        end
      end

      # Read file data into blocks
      #
      # @param io [IO] File IO object
      # @return [Array<String>] File blocks
      def read_file_blocks(io)
        blocks = []
        while (data = io.read(@block_size))
          # Pad last block if needed
          if data.bytesize < @block_size
            data += "\x00" * (@block_size - data.bytesize)
          end
          blocks << data
        end
        blocks
      end

      # Calculate total number of data blocks
      #
      # @return [Integer] Total blocks across all files
      def calculate_total_blocks
        @files.sum { |f| f.blocks.size }
      end

      # Calculate number of recovery blocks needed
      #
      # @param total_blocks [Integer] Total data blocks
      # @return [Integer] Number of recovery blocks
      def calculate_recovery_blocks(total_blocks)
        (total_blocks * @redundancy / 100.0).ceil
      end

      # Create main PAR2 index file
      #
      # @param base_name [String] Base name for file
      # @return [String] Path to created file
      def create_index_file(base_name)
        file_path = "#{base_name}.par2"

        File.open(file_path, "wb") do |io|
          write_main_packet(io)
          write_file_description_packets(io)
          write_ifsc_packets(io)
        end

        file_path
      end

      # Write main packet
      #
      # @param io [IO] Output IO
      def write_main_packet(io)
        packet_data = build_main_packet_data

        write_packet(io, PACKET_TYPE_MAIN, packet_data)
      end

      # Build main packet data
      #
      # @return [String] Packet data
      def build_main_packet_data
        data = String.new
        data << @set_id                          # Recovery Set ID (16 bytes)
        data << [@block_size].pack("Q<")         # Block size (8 bytes)
        data << [calculate_total_blocks].pack("Q<") # Recovery file count
        data << [@files.size].pack("Q<")         # Non-recovery file count

        # File IDs of all files in set
        @files.each do |file_info|
          data << file_info.file_id
        end

        data
      end

      # Write file description packets
      #
      # @param io [IO] Output IO
      def write_file_description_packets(io)
        @files.each do |file_info|
          packet_data = build_file_desc_packet_data(file_info)
          write_packet(io, PACKET_TYPE_FILE_DESC, packet_data)
        end
      end

      # Build file description packet data
      #
      # @param file_info [FileInfo] File information
      # @return [String] Packet data
      def build_file_desc_packet_data(file_info)
        data = String.new
        data << file_info.file_id                # File ID (16 bytes)
        data << file_info.hash_full              # File hash (16 bytes)
        data << file_info.hash_16k               # Hash of first 16K (16 bytes)
        data << [file_info.size].pack("Q<")      # File length (8 bytes)

        # Filename (null-terminated, padded to multiple of 4)
        filename = File.basename(file_info.path)
        data << filename
        data << "\x00"
        padding = (4 - ((filename.bytesize + 1) % 4)) % 4
        data << ("\x00" * padding) if padding > 0

        data
      end

      # Write IFSC packets (Input File Slice Checksum)
      #
      # @param io [IO] Output IO
      def write_ifsc_packets(io)
        @files.each do |file_info|
          file_info.blocks.each do |block|
            packet_data = build_ifsc_packet_data(file_info, block)
            write_packet(io, PACKET_TYPE_IFSC, packet_data)
          end
        end
      end

      # Build IFSC packet data
      #
      # @param file_info [FileInfo] File information
      # @param block [String] Block data
      # @return [String] Packet data
      def build_ifsc_packet_data(file_info, block)
        data = String.new
        data << file_info.file_id                # File ID (16 bytes)
        data << Digest::MD5.digest(block)        # Block hash (16 bytes)
        data << calculate_block_crc32(block)     # Block CRC32 (4 bytes)
        data
      end

      # Calculate CRC32 of block
      #
      # @param block [String] Block data
      # @return [String] Packed CRC32 (4 bytes)
      def calculate_block_crc32(block)
        require "zlib"
        [Zlib.crc32(block)].pack("L<")
      end

      # Create recovery volume files
      #
      # @param base_name [String] Base name for files
      # @param num_recovery [Integer] Number of recovery blocks
      # @param total_blocks [Integer] Total data blocks
      # @return [Array<String>] Paths to created files
      def create_recovery_volumes(base_name, num_recovery, total_blocks)
        return [] if num_recovery.zero?

        # Initialize Reed-Solomon encoder
        rs_encoder = ReedSolomon.new(block_size: @block_size)

        # Collect all data blocks from all files
        all_data_blocks = @files.flat_map(&:blocks)

        report_progress(10, "Generating recovery blocks (this may take a while)")

        # Generate parity blocks using Reed-Solomon encoding
        parity_blocks = rs_encoder.encode(all_data_blocks, num_parity: num_recovery)

        report_progress(60, "Writing recovery volume files")

        # Write recovery volumes using standard PAR2 naming scheme
        volume_files = write_recovery_volumes(base_name, parity_blocks)

        report_progress(90, "Finalizing recovery volumes")

        volume_files
      end

      # Write recovery volumes using PAR2 naming scheme
      #
      # PAR2 uses exponential distribution:
      # vol00+01.par2 = 1 block
      # vol01+02.par2 = 2 blocks
      # vol03+04.par2 = 4 blocks
      # vol07+08.par2 = 8 blocks
      # etc.
      #
      # @param base_name [String] Base name
      # @param parity_blocks [Array<String>] Parity blocks
      # @return [Array<String>] Created file paths
      def write_recovery_volumes(base_name, parity_blocks)
        volume_files = []
        current_block = 0
        volume_num = 0

        while current_block < parity_blocks.size
          # Calculate blocks in this volume (powers of 2)
          blocks_in_volume = 2**volume_num
          blocks_in_volume = [
            blocks_in_volume,
            parity_blocks.size - current_block
          ].min

          # Create volume file
          file_path = format(
            "%s.vol%02d+%02d.par2",
            base_name,
            current_block,
            blocks_in_volume
          )

          write_recovery_volume(
            file_path,
            parity_blocks[current_block, blocks_in_volume],
            current_block
          )

          volume_files << file_path
          current_block += blocks_in_volume
          volume_num += 1
        end

        volume_files
      end

      # Write single recovery volume file
      #
      # @param file_path [String] Output file path
      # @param blocks [Array<String>] Recovery blocks
      # @param start_exponent [Integer] Starting exponent
      def write_recovery_volume(file_path, blocks, start_exponent)
        File.open(file_path, "wb") do |io|
          # Write main packet (same as index file)
          write_main_packet(io)

          # Write recovery slice packets
          blocks.each_with_index do |block, idx|
            exponent = start_exponent + idx
            packet_data = build_recovery_packet_data(block, exponent)
            write_packet(io, PACKET_TYPE_RECOVERY, packet_data)
          end
        end
      end

      # Build recovery slice packet data
      #
      # @param block [String] Recovery block data
      # @param exponent [Integer] Recovery exponent
      # @return [String] Packet data
      def build_recovery_packet_data(block, exponent)
        data = String.new
        data << [exponent].pack("L<")            # Exponent (4 bytes)
        data << block                            # Recovery data
        data
      end

      # Write packet with header
      #
      # @param io [IO] Output IO
      # @param packet_type [String] Packet type identifier
      # @param packet_data [String] Packet data
      def write_packet(io, packet_type, packet_data)
        # Calculate packet length
        # Header: 8 bytes magic + 8 bytes length + 16 bytes hash + 16 bytes set_id
        #         + 16 bytes type = 64 bytes
        # Plus packet data
        packet_length = 64 + packet_data.bytesize

        # Build complete packet
        packet = String.new
        packet << PACKET_SIGNATURE                # Magic (8 bytes)
        packet << [packet_length].pack("Q<")      # Length (8 bytes)

        # Calculate packet hash (MD5 of everything after length field)
        packet_body = String.new
        packet_body << @set_id                    # Recovery Set ID (16 bytes)
        packet_body << packet_type                # Packet type (16 bytes)
        packet_body << packet_data                # Packet data

        packet_hash = Digest::MD5.digest(packet_body)
        packet << packet_hash                     # Hash (16 bytes)
        packet << packet_body                     # Body

        # Write to file
        io.write(packet)
      end

      # Report progress if callback provided
      #
      # @param percent [Integer] Completion percentage
      # @param message [String] Progress message
      def report_progress(percent, message)
        @progress_callback&.call(percent, message)
      end

      # Analyze file and calculate hashes/blocks
      #
      # @param file_path [String] Path to file
      # @return [FileInfo] File information
      def analyze_file(file_path)
        File.open(file_path, "rb") do |io|
          file_size = io.size

          # Read first 16KB for hash
          first_16k = io.read(16384) || ""
          hash_16k = Digest::MD5.digest(first_16k)

          # Calculate full file hash
          io.rewind
          hash_full = Digest::MD5.file(file_path).digest

          # Generate file ID
          basename = File.basename(file_path)
          file_id_string = "#{basename}\x00#{file_size}"
          file_id = Digest::MD5.digest(file_id_string)

          # Read all blocks
          io.rewind
          blocks = read_file_blocks(io)

          FileInfo.new(
            path: file_path,
            file_id: file_id,
            hash_16k: hash_16k,
            hash_full: hash_full,
            size: file_size,
            blocks: blocks
          )
        end
      end
    end
  end
end