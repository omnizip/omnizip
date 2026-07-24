# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # RAR recovery record handling
      # Parses and manages recovery records for error correction
      class RecoveryRecord
        attr_reader :version, :type, :protection_percent, :block_size,
                    :recovery_blocks, :protected_size, :recovery_size,
                    :reed_solomon_params, :external_files

        # Recovery record types
        TYPE_INTEGRATED = :integrated  # Inside archive
        TYPE_EXTERNAL = :external      # Separate .rev files

        # Initialize recovery record
        #
        # @param version [Integer] RAR version (4 or 5)
        def initialize(version)
          @version = version
          @type = TYPE_INTEGRATED
          @protection_percent = 0
          @block_size = 0
          @recovery_blocks = 0
          @protected_size = 0
          @recovery_size = 0
          @reed_solomon_params = {}
          @external_files = []
        end

        # Check if recovery records are available
        #
        # @return [Boolean] true if recovery available
        def available?
          @recovery_blocks.positive? || @external_files.any?
        end

        # Check if using external .rev files
        #
        # @return [Boolean] true if external recovery
        def external?
          @type == TYPE_EXTERNAL
        end

        # Parse recovery record from archive
        #
        # @param io [IO] Input stream
        # @param flags [Integer] Archive flags
        # @return [Boolean] true if recovery record found
        def parse_from_archive(io, flags)
          return false unless recovery_flag_set?(flags)

          if @version == 5
            parse_rar5_recovery(io)
          else
            parse_rar4_recovery(io)
          end
        end

        # Detect external .rev files
        #
        # @param archive_path [String] Path to main archive
        # @return [Array<String>] Paths to .rev files
        def detect_external_files(archive_path)
          dir = File.dirname(archive_path)
          basename = File.basename(archive_path, ".*")

          # Check for RAR5 naming (.part01.rar.rev)
          if archive_path.match?(/\.part\d+\.rar$/i)
            detect_rar5_rev_files(dir, archive_path)
          else
            # RAR4 naming (.r00.rev, .r01.rev)
            detect_rar4_rev_files(dir, basename)
          end
        end

        # Load external recovery files
        #
        # @param rev_files [Array<String>] Paths to .rev files
        def load_external_files(rev_files)
          @external_files = rev_files.select { |f| File.exist?(f) }
          @type = TYPE_EXTERNAL if @external_files.any?
        end

        # Get total recovery data size
        #
        # @return [Integer] Total recovery bytes
        def total_recovery_size
          if external?
            @external_files.sum { |f| File.size(f) }
          else
            @recovery_size
          end
        end

        # Calculate protection level
        #
        # @return [Float] Protection percentage
        def protection_level
          return 0.0 if @protected_size.zero?

          (@recovery_size.to_f / @protected_size * 100).round(2)
        end

        private

        # Check if recovery flag is set in archive flags
        #
        # @param flags [Integer] Archive flags
        # @return [Boolean] true if recovery flag set
        def recovery_flag_set?(flags)
          flags.anybits?(Constants::ARCHIVE_RECOVERY)
        end

        # Parse RAR5 recovery record
        #
        # @param io [IO] Input stream
        # @return [Boolean] true if parsed successfully
        def parse_rar5_recovery(io)
          # RAR5 recovery record structure
          # Read block header
          block_type = read_vint(io)
          return false unless block_type == Constants::RAR5_HEADER_SERVICE

          block_flags = read_vint(io)
          _extra_size = read_vint(io) if block_flags.anybits?(0x0001)

          # Read recovery parameters
          @block_size = read_vint(io)
          @recovery_blocks = read_vint(io)
          @protected_size = read_vint(io)

          # Reed-Solomon parameters for RAR5
          @reed_solomon_params[:data_blocks] = read_vint(io)
          @reed_solomon_params[:parity_blocks] = read_vint(io)

          @recovery_size = @block_size * @recovery_blocks
          @protection_percent = protection_level.to_i

          true
        rescue StandardError
          false
        end

        # Parse RAR4 recovery record
        #
        # @param io [IO] Input stream
        # @return [Boolean] true if parsed successfully
        def parse_rar4_recovery(io)
          # RAR4 old recovery record structure
          # Skip to recovery block
          block_type = io.read(1)&.unpack1("C")
          return false unless block_type == Constants::BLOCK_OLD_RECOVERY

          # Read block header
          _block_flags = io.read(2)&.unpack1("v")
          io.read(2)&.unpack1("v")

          # Read recovery data size
          @recovery_size = io.read(4)&.unpack1("V") || 0
          @protected_size = io.read(4)&.unpack1("V") || 0
          @recovery_blocks = io.read(2)&.unpack1("v") || 0

          if @recovery_blocks.positive?
            @block_size = @recovery_size / @recovery_blocks
          end
          @protection_percent = protection_level.to_i

          true
        rescue StandardError
          false
        end

        # Detect RAR5 external .rev files
        #
        # @param dir [String] Directory path
        # @param archive_path [String] Archive path
        # @return [Array<String>] .rev file paths
        def detect_rar5_rev_files(_dir, archive_path)
          rev_files = []

          # Check for .partNN.rar.rev files
          if archive_path =~ /^(.+)(\.part\d+\.rar)$/i
            base_name = Regexp.last_match(1)
            Regexp.last_match(2)

            (1..999).each do |i|
              rev_path = format("%s.part%02d.rar.rev", base_name, i)
              break unless File.exist?(rev_path)

              rev_files << rev_path
            end
          end

          rev_files
        end

        # Detect RAR4 external .rev files
        #
        # @param dir [String] Directory path
        # @param basename [String] Archive base name
        # @return [Array<String>] .rev file paths
        def detect_rar4_rev_files(dir, basename)
          rev_files = []

          # Check for archive.rev
          main_rev = File.join(dir, "#{basename}.rev")
          rev_files << main_rev if File.exist?(main_rev)

          # Check for .rNN.rev files
          (0..99).each do |i|
            rev_path = File.join(dir, format("%s.r%02d.rev", basename, i))
            break unless File.exist?(rev_path)

            rev_files << rev_path
          end

          rev_files
        end

        # Read variable-length integer (RAR5)
        #
        # @param io [IO] Input stream
        # @return [Integer] Decoded integer
        def read_vint(io)
          result = 0
          shift = 0

          loop do
            byte = io.read(1)&.unpack1("C")
            raise "Unexpected EOF" unless byte

            result |= (byte & 0x7F) << shift
            break if byte.nobits?(0x80)

            shift += 7
          end

          result
        end
      end
    end
  end
end
