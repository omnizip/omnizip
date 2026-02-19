# frozen_string_literal: true

require_relative "../header"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module MultiVolume
          # Volume writer for multi-volume archives
          #
          # This class writes individual .rar volume files with proper
          # RAR5 headers and volume-specific flags.
          #
          # @example Write a volume
          #   writer = VolumeWriter.new('archive.part1.rar', volume_number: 1, is_last: false)
          #   writer.write_signature
          #   writer.write_main_header
          #   writer.write_file_data(file_header, compressed_data)
          #   writer.write_end_header
          #   writer.close
          class VolumeWriter
            # Main header flags for volume archives
            # NOTE: Bits 0-1 are reserved for common flags (EXTRA_AREA, DATA_AREA)
            # Use bits 2+ for format-specific flags
            VOLUME_ARCHIVE_FLAG = 0x0004  # Bit 2: This is a volume archive
            VOLUME_NUMBER_FLAG  = 0x0008  # Bit 3: Volume number present in extra area

            # End header flags
            VOLUME_END_FLAG = 0x0001 # Not the last volume (more volumes follow)

            # @return [String] Volume file path
            attr_reader :path

            # @return [Integer] Volume number (1-based)
            attr_reader :volume_number

            # @return [Boolean] Is this the last volume?
            attr_reader :is_last

            # @return [IO] File handle
            attr_reader :io

            # Initialize volume writer
            #
            # @param path [String] Output volume file path
            # @param volume_number [Integer] Volume number (1-based)
            # @param is_last [Boolean] Is this the last volume?
            def initialize(path, volume_number:, is_last: false)
              @path = path
              @volume_number = volume_number
              @is_last = is_last
              @io = nil
            end

            # Open volume file for writing
            #
            # @return [void]
            def open
              @io = File.open(@path, "wb")
            end

            # Close volume file
            #
            # @return [void]
            def close
              @io&.close
              @io = nil
            end

            # Write with automatic open/close
            #
            # @yield [writer] Yields self for writing operations
            # @return [void]
            def write
              open
              yield self
            ensure
              close
            end

            # Write RAR5 signature
            #
            # @return [void]
            def write_signature
              raise "Volume not open" unless @io

              # RAR5 signature: "Rar!\x1A\x07\x01\x00"
              signature = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01,
                           0x00].pack("C*")
              @io.write(signature)
            end

            # Write Main header with volume flags
            #
            # @return [void]
            def write_main_header
              raise "Volume not open" unless @io

              # Set volume-specific flags
              flags = VOLUME_ARCHIVE_FLAG

              # Add volume number in extra area for volumes 2+
              extra_area = nil
              if @volume_number > 1
                flags |= VOLUME_NUMBER_FLAG
                # Volume number as VINT in extra area
                extra_area = VINT.encode(@volume_number).pack("C*")
              end

              header = MainHeader.new(flags: flags)

              # Manually add extra area if needed
              if extra_area
                # We need to modify the header to include extra area
                # For now, use basic header without extra area (simplified)
                # TODO: Enhance MainHeader to support extra_area parameter
              end

              @io.write(header.encode)
            end

            # Write file data (header + compressed data)
            #
            # @param file_header [FileHeader] File header
            # @param compressed_data [String] Compressed file data
            # @return [void]
            def write_file_data(file_header, compressed_data)
              raise "Volume not open" unless @io

              @io.write(file_header.encode)
              @io.write(compressed_data)
            end

            # Write End header with volume flags
            #
            # @return [void]
            def write_end_header
              raise "Volume not open" unless @io

              # Set END_OF_ARCHIVE flags
              flags = 0
              flags | VOLUME_END_FLAG unless @is_last

              header = EndHeader.new
              # Note: EndHeader doesn't support custom flags yet
              # For v0.5.0, we'll use basic end header
              # TODO: Enhance EndHeader to support volume flags

              @io.write(header.encode)
            end

            # Generate volume filename from base name
            #
            # @param base_path [String] Base archive path (e.g., "archive.rar")
            # @param volume_number [Integer] Volume number (1-based)
            # @param naming [String] Naming pattern ("part" or "volume")
            # @return [String] Volume filename (e.g., "archive.part1.rar")
            def self.volume_filename(base_path, volume_number, naming: "part")
              dir = File.dirname(base_path)
              basename = File.basename(base_path, ".*")
              ext = File.extname(base_path)

              volume_name = case naming
                            when "part"
                              "#{basename}.part#{volume_number}#{ext}"
                            when "volume"
                              "#{basename}.vol#{volume_number}#{ext}"
                            when "numeric"
                              # Simple numeric suffix: archive.rar, archive.r00, archive.r01, etc.
                              if volume_number == 1
                                "#{basename}#{ext}"
                              else
                                # Volume 2 => r00, Volume 3 => r01, etc.
                                "#{basename}.r#{format('%02d',
                                                       volume_number - 2)}"
                              end
                            else
                              "#{basename}.part#{volume_number}#{ext}"
                            end

              # Handle relative vs absolute paths
              if dir == "."
                volume_name
              else
                File.join(dir, volume_name)
              end
            end
          end
        end
      end
    end
  end
end
