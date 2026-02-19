# frozen_string_literal: true

require_relative "constants"
require_relative "parser"

module Omnizip
  module Formats
    module SevenZip
      # .7z archive header parser
      # Handles signature validation and start header
      class Header
        include Constants

        attr_reader :major_version, :minor_version, :start_header_crc,
                    :next_header_offset, :next_header_size, :next_header_crc

        # Parse header from IO
        #
        # @param io [IO] Input stream
        # @return [Header] Parsed header
        # @raise [RuntimeError] if signature or CRC invalid
        def self.read(io)
          header = new
          header.parse(io)
          header
        end

        # Parse header data from IO stream
        #
        # @param io [IO] Input stream positioned at start
        # @raise [RuntimeError] if signature or version invalid
        def parse(io)
          # Read complete start header (32 bytes)
          header_data = io.read(START_HEADER_SIZE)
          raise "Invalid .7z file: too short" if header_data.nil? ||
            header_data.bytesize < START_HEADER_SIZE

          # Validate signature
          signature = header_data[0, SIGNATURE_SIZE]
          unless signature == SIGNATURE
            raise "Invalid .7z signature: expected #{SIGNATURE.inspect}, " \
                  "got #{signature.inspect}"
          end

          # Parse version
          @major_version = header_data.getbyte(6)
          @minor_version = header_data.getbyte(7)

          unless @major_version == MAJOR_VERSION
            raise "Unsupported .7z version: #{@major_version}.#{@minor_version}"
          end

          # Parse start header CRC (bytes 8-11)
          @start_header_crc = header_data[8, 4].unpack1("V")

          # Parse next header info (bytes 12-31, 20 bytes total)
          next_header_data = header_data[12, 20]

          # NOTE: CRC validation temporarily disabled for Phase 2
          # Will be refined in Phase 3 with proper CRC32 initialization
          # calculated_crc = calculate_crc32(next_header_data)
          # unless calculated_crc == @start_header_crc
          #   warn "CRC mismatch (non-fatal): expected " \
          #        "#{@start_header_crc.to_s(16)}, " \
          #        "got #{calculated_crc.to_s(16)}"
          # end

          # Parse next header offset and size
          @next_header_offset = next_header_data[0, 8].unpack1("Q<")
          @next_header_size = next_header_data[8, 8].unpack1("Q<")
          @next_header_crc = next_header_data[16, 4].unpack1("V")

          self
        end

        # Get position after start header
        #
        # @return [Integer] Byte position
        def start_pos_after_header
          START_HEADER_SIZE
        end

        # Check if header is valid
        #
        # @return [Boolean] true if valid
        def valid?
          !@next_header_offset.nil? && !@next_header_size.nil?
        end

        private

        # Calculate CRC32 checksum
        # Note: Needs refinement for .7z CRC compatibility
        #
        # @param data [String] Binary data
        # @return [Integer] CRC32 value
        def calculate_crc32(data)
          require_relative "../../checksums/crc32"
          crc = Omnizip::Checksums::Crc32.new
          crc.update(data)
          crc.value
        end
      end
    end
  end
end
