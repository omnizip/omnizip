# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        module MultiVolume
          # Volume splitter for multi-volume archives
          #
          # This class handles splitting compressed data streams across
          # multiple volumes while respecting size boundaries and file atomicity.
          #
          # @example Split data across volumes
          #   splitter = VolumeSplitter.new(max_volume_size: 10_485_760)
          #   splitter.start_volume(1)
          #   splitter.write_to_current_volume(file1_data)
          #   if !splitter.can_fit_in_current_volume?(file2_data.bytesize)
          #     splitter.finalize_volume
          #     splitter.start_volume(2)
          #   end
          class VolumeSplitter
            # @return [Integer] Maximum size per volume in bytes
            attr_reader :max_volume_size

            # @return [Integer] Current volume number (1-based)
            attr_reader :current_volume_number

            # @return [Integer] Bytes written to current volume
            attr_reader :current_volume_bytes

            # @return [Array<Hash>] Volume metadata
            attr_reader :volumes

            # Minimum space reserved for headers (signature + main + end headers)
            HEADER_OVERHEAD = 1024

            # Initialize volume splitter
            #
            # @param max_volume_size [Integer] Maximum size per volume in bytes
            def initialize(max_volume_size:)
              @max_volume_size = max_volume_size
              @current_volume_number = 0
              @current_volume_bytes = 0
              @current_volume_data = []
              @volumes = []
            end

            # Start a new volume
            #
            # @param volume_number [Integer] Volume number (1-based)
            # @return [void]
            def start_volume(volume_number)
              @current_volume_number = volume_number
              @current_volume_bytes = HEADER_OVERHEAD # Reserve space for headers
              @current_volume_data = []
            end

            # Check if data can fit in current volume
            #
            # @param data_size [Integer] Size of data to write
            # @return [Boolean] true if data fits, false if new volume needed
            def can_fit_in_current_volume?(data_size)
              (@current_volume_bytes + data_size) <= @max_volume_size
            end

            # Get remaining space in current volume
            #
            # @return [Integer] Bytes available
            def remaining_space
              @max_volume_size - @current_volume_bytes
            end

            # Write data to current volume
            #
            # @param data [String] Data to write
            # @return [void]
            # @raise [RuntimeError] if no volume is active
            # @raise [RuntimeError] if data doesn't fit
            def write_to_current_volume(data)
              raise "No active volume" if @current_volume_number.zero?
              raise "Data doesn't fit in current volume" unless can_fit_in_current_volume?(data.bytesize)

              @current_volume_data << data
              @current_volume_bytes += data.bytesize
            end

            # Finalize current volume
            #
            # @return [Hash] Volume metadata
            def finalize_volume
              volume_info = {
                number: @current_volume_number,
                size: @current_volume_bytes,
                data: @current_volume_data.join,
              }

              @volumes << volume_info
              volume_info
            end

            # Calculate optimal file distribution across volumes
            #
            # This method determines how to distribute files across volumes
            # to minimize volume count while respecting atomicity.
            #
            # @param files [Array<Hash>] File information with :compressed_size
            # @return [Array<Array<Integer>>] Volume assignments (file indices per volume)
            def calculate_file_distribution(files)
              distribution = []
              current_volume_files = []
              current_volume_used = HEADER_OVERHEAD

              files.each_with_index do |file, idx|
                file_size = file[:compressed_size] + file[:header_size]

                # Check if file fits in current volume
                if (current_volume_used + file_size) <= @max_volume_size
                  current_volume_files << idx
                  current_volume_used += file_size
                else
                  # Start new volume
                  distribution << current_volume_files unless current_volume_files.empty?
                  current_volume_files = [idx]
                  current_volume_used = HEADER_OVERHEAD + file_size

                  # Check if single file exceeds volume size
                  if current_volume_used > @max_volume_size
                    # File must span multiple volumes (not implemented yet)
                    # For now, just place it in its own volume
                    distribution << [idx]
                    current_volume_files = []
                    current_volume_used = HEADER_OVERHEAD
                  end
                end
              end

              # Add final volume if not empty
              distribution << current_volume_files unless current_volume_files.empty?

              distribution
            end

            # Check if archive needs splitting
            #
            # @param total_size [Integer] Total archive size
            # @return [Boolean] true if splitting needed
            def self.needs_splitting?(total_size, max_volume_size)
              total_size > max_volume_size
            end
          end
        end
      end
    end
  end
end
