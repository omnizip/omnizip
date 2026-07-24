# frozen_string_literal: true

require "tempfile"
require "fileutils"

module Omnizip
  module Formats
    module Msi
      # MSI CAB Extractor
      #
      # Handles extraction of files from embedded or external cabinet files.
      # MSI packages can have cabinets embedded in the _Streams table or
      # as separate .cab files alongside the MSI.
      class CabExtractor
        include Omnizip::Formats::Msi::Constants

        # @return [Ole::Storage] OLE storage
        attr_reader :ole

        # @return [Array<Hash>] Media table data
        attr_reader :media_table

        # @return [String] Path to MSI file (for external CAB resolution)
        attr_reader :msi_path

        # @return [Proc] Stream reader method
        attr_reader :read_stream

        # Initialize CAB extractor
        #
        # @param ole [Ole::Storage] OLE storage object
        # @param media_table [Array<Hash>] Parsed Media table rows
        # @param msi_path [String] Path to MSI file
        # @param stream_reader [Proc] Method to read streams
        def initialize(ole, media_table, msi_path, stream_reader)
          @ole = ole
          @media_table = media_table || []
          @msi_path = msi_path
          @read_stream = stream_reader
        end

        # Extract all cabinets to temporary files
        #
        # @return [Hash] Map of cabinet name => temp file path
        def extract_cabinets
          cabinets = {}

          @media_table.each do |media|
            cab_name = media["Cabinet"]
            next if cab_name.nil? || cab_name.empty?

            cab_data = get_cabinet_data(cab_name)
            next if cab_data.nil? || cab_data.empty?

            # Write to temp file
            temp_file = Tempfile.create(["msi_cab_", ".cab"])
            temp_file.binmode
            temp_file.write(cab_data)
            temp_file.flush
            temp_file.close

            cabinets[media["DiskId"]] = {
              path: temp_file.path,
              name: cab_name,
              last_sequence: media["LastSequence"],
              temp_file: temp_file,
            }
          end

          cabinets
        end

        # Get cabinet data for a media entry
        #
        # @param cabinet_name [String] Cabinet name from Media table
        # @return [String, nil] Cabinet binary data or nil
        def get_cabinet_data(cabinet_name)
          return nil if cabinet_name.nil? || cabinet_name.empty?

          if cabinet_name.start_with?(EMBEDDED_CAB_PREFIX)
            # Embedded cabinet
            extract_embedded_cabinet(cabinet_name[1..])
          else
            # External cabinet file
            read_external_cabinet(cabinet_name)
          end
        end

        # Find the cabinet containing a file by sequence number
        #
        # @param sequence [Integer] File sequence number
        # @param cabinets [Hash] Cabinet info from extract_cabinets
        # @return [Hash, nil] Cabinet info or nil
        def find_cabinet_for_sequence(sequence, cabinets)
          # Sort by LastSequence and find the cabinet where sequence <= LastSequence
          sorted = cabinets.values.sort_by { |c| c[:last_sequence] }
          sorted.find { |c| sequence <= c[:last_sequence] }
        end

        private

        # Extract embedded cabinet data
        #
        # Embedded cabinets can be in:
        # 1. _Streams table (most common)
        # 2. Direct OLE stream (rare)
        #
        # @param stream_name [String] Stream name (without # prefix)
        # @return [String, nil] Cabinet data or nil
        def extract_embedded_cabinet(stream_name)
          return nil if stream_name.nil? || stream_name.empty?

          # Try to read from OLE directly using various name encodings
          candidates = build_stream_name_candidates(stream_name)

          candidates.each do |name|
            data = @read_stream.call(name)
            return data if data && !data.empty? && valid_cab?(data)
          end

          # Also try without # prefix but with standard prefixes
          data = @read_stream.call(stream_name)
          return data if data && !data.empty? && valid_cab?(data)

          nil
        end

        # Build possible encoded stream name candidates
        #
        # @param name [String] Base stream name
        # @return [Array<String>] Possible stream names
        def build_stream_name_candidates(name)
          candidates = []

          # Try direct name
          candidates << name

          # Try with MSI stream name encoding prefix
          # Use binary encoding for the prefix byte
          utf16le = name.encode("UTF-16LE")
          candidates << ("\x01".b << utf16le.dup.force_encoding("BINARY"))
          candidates << ("\x05".b << utf16le.dup.force_encoding("BINARY"))

          # Try without any prefix (plain ASCII)
          candidates << name

          candidates.uniq
        end

        # Check if data is a valid cabinet file
        #
        # @param data [String] Binary data
        # @return [Boolean] true if valid CAB signature
        def valid_cab?(data)
          return false if data.nil? || data.bytesize < 4

          # Check for MSCF signature
          data[0, 4] == "MSCF"
        end

        # Read external cabinet file
        #
        # External cabinets are located in the same directory as the MSI.
        #
        # @param cabinet_name [String] Cabinet filename
        # @return [String, nil] Cabinet data or nil
        def read_external_cabinet(cabinet_name)
          return nil if @msi_path.nil?

          cab_path = File.join(File.dirname(@msi_path), cabinet_name)

          begin
            File.binread(cab_path) if File.exist?(cab_path)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
