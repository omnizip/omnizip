# frozen_string_literal: true

require_relative "coder_chain"
require_relative "../../checksums/crc32"
require "stringio"

module Omnizip
  module Formats
    module SevenZip
      # Decompresses .7z streams using coder chains
      # Handles packed stream extraction and CRC validation
      class StreamDecompressor
        attr_reader :archive_io, :folder, :chain_config

        # Initialize decompressor
        #
        # @param archive_io [IO] Archive file handle
        # @param folder [Models::Folder] Folder specification
        # @param pack_pos [Integer] Position of packed data
        # @param pack_size [Integer] Size of packed data
        # @param header [Header, nil] Optional header for split archive handling
        def initialize(archive_io, folder, pack_pos, pack_size, header = nil)
          @archive_io = archive_io
          @folder = folder
          @pack_pos = pack_pos
          @pack_size = pack_size
          @header = header
          @chain_config = CoderChain.build_from_folder(folder)
        end

        # Decompress stream to output
        #
        # @param size [Integer] Expected uncompressed size
        # @return [String] Decompressed data
        # @raise [RuntimeError] on decompression error
        def decompress(size)
          # Seek to packed data
          @archive_io.seek(@pack_pos)

          # For multi-volume archives, pack_size from stream_info may be incomplete.
          # For solid archives spanning volumes, the actual compressed data extends
          # from pack_pos to where the next header starts.
          if @archive_io.is_a?(SplitArchiveReader::MultiVolumeIO) && @header
            # next_header_offset is relative to start_pos_after_header
            # Actual packed data size is from pack_pos to next header position
            next_header_position = @header.start_pos_after_header + @header.next_header_offset
            actual_pack_size = next_header_position - @pack_pos
            packed_data = @archive_io.read(actual_pack_size)
          else
            # Regular single-file archive: use pack_size from stream info
            packed_data = @archive_io.read(@pack_size)
          end

          return packed_data if @chain_config.nil? # No compression

          # Get algorithm
          algo_sym = @chain_config[:algorithm]
          return packed_data unless algo_sym # Copy method

          # Get algorithm class
          algo_class = AlgorithmRegistry.get(algo_sym)
          raise "Algorithm not found: #{algo_sym}" unless algo_class

          # Decompress
          input_io = StringIO.new(packed_data)
          output_io = StringIO.new
          output_io.set_encoding("BINARY")

          # Build options from coder properties for 7-Zip format
          decoder_options = build_decoder_options

          decoder = algo_class.new(decoder_options)
          decoder.decompress(input_io, output_io, size: size)

          result = output_io.string

          # Apply filters if present
          if @chain_config[:filters] && !@chain_config[:filters].empty?
            @chain_config[:filters].reverse_each do |filter_sym|
              filter_class = FilterRegistry.get(filter_sym)
              next unless filter_class

              filter = filter_class.new
              filtered = StringIO.new
              filter.reverse(StringIO.new(result), filtered)
              result = filtered.string
            end
          end

          result
        end

        # Decompress and verify CRC
        #
        # @param size [Integer] Expected uncompressed size
        # @param expected_crc [Integer, nil] Expected CRC32 value
        # @return [String] Decompressed data
        # @raise [RuntimeError] if CRC mismatch
        def decompress_and_verify(size, expected_crc = nil)
          data = decompress(size)

          if expected_crc
            crc = Omnizip::Checksums::Crc32.new
            crc.update(data)
            actual_crc = crc.value

            unless actual_crc == expected_crc
              raise "CRC mismatch: expected 0x#{expected_crc.to_s(16)}, " \
                    "got 0x#{actual_crc.to_s(16)}"
            end
          end

          data
        end

        private

        # Build decoder options from coder properties
        #
        # For 7-Zip format, coder properties contain algorithm-specific data.
        # For LZMA2, it's a single byte encoding the dictionary size.
        #
        # @return [Hash] Decoder options
        def build_decoder_options
          return {} unless @chain_config

          options = {}
          properties = @chain_config[:properties]

          if properties && !properties.empty?
            algo_sym = @chain_config[:algorithm]

            case algo_sym
            when :lzma2
              # LZMA2 properties: single byte encoding dictionary size
              prop_byte = properties.getbyte(0)
              dict_size = Omnizip::Algorithms::LZMA2::Properties.decode_dict_size(prop_byte)
              options[:raw_mode] = true # No property byte in data stream
              options[:dict_size] = dict_size
            when :lzma
              # LZMA properties: 5 bytes (prop byte + dict size)
              # Format: 1 byte (lc/lp/pb) + 4 bytes (dict size LE)
              if properties.bytesize >= 5
                props_byte = properties.getbyte(0)
                dict_size = properties[1, 4].unpack1("V")
                # Use lzma2_mode to skip header reading - 7-Zip provides properties separately
                options[:lzma2_mode] = true
                options[:lc] = props_byte % 9
                remainder = props_byte / 9
                options[:lp] = remainder % 5
                options[:pb] = remainder / 5
                options[:dict_size] = dict_size
              end
            end
          end

          options
        end
      end
    end
  end
end
