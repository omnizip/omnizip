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
        def initialize(archive_io, folder, pack_pos, pack_size)
          @archive_io = archive_io
          @folder = folder
          @pack_pos = pack_pos
          @pack_size = pack_size
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
          packed_data = @archive_io.read(@pack_size)

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

          decoder = algo_class.new
          decoder.decompress(input_io, output_io, size)

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
      end
    end
  end
end
