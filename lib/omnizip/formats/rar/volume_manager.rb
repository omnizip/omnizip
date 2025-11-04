# frozen_string_literal: true

require_relative "models/rar_volume"

module Omnizip
  module Formats
    module Rar
      # Manages multi-volume RAR archives
      # Handles volume detection, sequencing, and coordination
      class VolumeManager
        attr_reader :volumes, :base_path

        # Initialize volume manager
        #
        # @param path [String] Path to any volume in the set
        def initialize(path)
          @base_path = path
          @volumes = []
          detect_volumes
        end

        # Get total number of volumes
        #
        # @return [Integer] Number of volumes
        def volume_count
          @volumes.size
        end

        # Check if this is a multi-volume archive
        #
        # @return [Boolean] true if multi-volume
        def multi_volume?
          @volumes.size > 1
        end

        # Get first volume
        #
        # @return [Models::RarVolume, nil] First volume or nil
        def first_volume
          @volumes.find(&:first?)
        end

        # Get last volume
        #
        # @return [Models::RarVolume, nil] Last volume or nil
        def last_volume
          @volumes.find(&:last?)
        end

        # Get volume by number
        #
        # @param number [Integer] Volume number (0-based)
        # @return [Models::RarVolume, nil] Volume or nil
        def volume_at(number)
          @volumes.find { |v| v.volume_number == number }
        end

        # Get all volume paths
        #
        # @return [Array<String>] Paths to all volumes
        def volume_paths
          @volumes.map(&:path)
        end

        # Get recovery files for volumes
        #
        # @return [Array<String>] Paths to .rev files
        def recovery_files
          rev_files = []

          @volumes.each do |volume|
            # Check for .rev file for this volume
            rev_path = "#{volume.path}.rev"
            rev_files << rev_path if File.exist?(rev_path)
          end

          rev_files
        end

        # Validate volume sequence
        #
        # @return [Boolean] true if all volumes exist and sequence is valid
        def valid_sequence?
          return true unless multi_volume?

          # Check all volumes exist
          return false unless @volumes.all?(&:exist?)

          # Check sequence is continuous
          expected_numbers = (0...@volumes.size).to_a
          actual_numbers = @volumes.map(&:volume_number).sort
          expected_numbers == actual_numbers
        end

        private

        # Detect all volumes in the set
        def detect_volumes
          if rar5_naming?
            detect_rar5_volumes
          else
            detect_rar4_volumes
          end

          # Mark first and last
          @volumes.first.is_first = true if @volumes.any?
          @volumes.last.is_last = true if @volumes.any?
        end

        # Check if using RAR5 naming (.partNN.rar)
        #
        # @return [Boolean] true if RAR5 naming
        def rar5_naming?
          @base_path.match?(/\.part\d+\.rar$/i)
        end

        # Detect RAR5 volumes (.part01.rar, .part02.rar, ...)
        def detect_rar5_volumes
          # Extract base name and current part number
          if @base_path =~ /^(.+)\.part(\d+)\.rar$/i
            base_name = Regexp.last_match(1)
            Regexp.last_match(2).to_i

            # Find all volumes
            volume_num = 0
            (1..999).each do |i|
              path = format("%s.part%02d.rar", base_name, i)
              break unless File.exist?(path)

              volume = Models::RarVolume.new(path, volume_num)
              @volumes << volume
              volume_num += 1
            end
          else
            # Single volume
            @volumes << Models::RarVolume.new(@base_path, 0)
          end
        end

        # Detect RAR4 volumes (.rar, .r00, .r01, ...)
        def detect_rar4_volumes
          dir = File.dirname(@base_path)
          basename = File.basename(@base_path, ".*")

          # Check for .rar file
          rar_path = File.join(dir, "#{basename}.rar")
          if File.exist?(rar_path)
            @volumes << Models::RarVolume.new(rar_path, 0)

            # Find .r00, .r01, .r02, ...
            volume_num = 1
            (0..99).each do |i|
              path = File.join(dir, format("%s.r%02d", basename, i))
              break unless File.exist?(path)

              volume = Models::RarVolume.new(path, volume_num)
              @volumes << volume
              volume_num += 1
            end
          else
            # Single volume
            @volumes << Models::RarVolume.new(@base_path, 0)
          end
        end
      end
    end
  end
end
