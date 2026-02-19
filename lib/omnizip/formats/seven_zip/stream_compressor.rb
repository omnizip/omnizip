# frozen_string_literal: true

require "stringio"
require_relative "../../checksums/crc32"

module Omnizip
  module Formats
    module SevenZip
      # Compresses data streams using coder chains
      # Opposite of StreamDecompressor - applies compression algorithms
      class StreamCompressor
        attr_reader :algorithm, :level, :filters

        # Initialize compressor
        #
        # @param algorithm [Symbol] Compression algorithm
        # @param level [Integer] Compression level (1-9)
        # @param filters [Array<Symbol>] Filter chain
        def initialize(algorithm: :lzma2, level: 5, filters: [])
          @algorithm = algorithm
          @level = level
          @filters = Array(filters)
        end

        # Compress data
        #
        # @param data [String] Uncompressed data
        # @return [String] Compressed data
        def compress(data)
          result = data

          # Apply filters first
          @filters.each do |filter_sym|
            filter_class = FilterRegistry.get(filter_sym)
            next unless filter_class

            filter = filter_class.new
            input_io = StringIO.new(result)
            output_io = StringIO.new
            output_io.set_encoding("BINARY")
            filter.encode(input_io, output_io)
            result = output_io.string
          end

          # Apply compression algorithm
          if @algorithm && @algorithm != :copy
            algo_class = AlgorithmRegistry.get(@algorithm)
            raise "Algorithm not found: #{@algorithm}" unless algo_class

            encoder = algo_class.new
            input_io = StringIO.new(result)
            output_io = StringIO.new
            output_io.set_encoding("BINARY")

            # For 7-Zip format, use raw_mode (no property byte in compressed data)
            # The properties are encoded in the 7-Zip header instead
            encoder.compress(input_io, output_io, { raw_mode: true, standalone: false })
            result = output_io.string
          end

          result
        end

        # Compress multiple files into single stream (solid compression)
        #
        # @param file_entries [Array<Models::FileEntry>] Files to compress
        # @return [Hash] Compression result with packed/unpacked sizes
        def compress_files(file_entries)
          # Concatenate all file data
          combined_data = String.new(encoding: "BINARY")
          unpack_sizes = []
          crcs = []

          file_entries.each do |entry|
            next unless entry.has_stream? && entry.source_path

            data = File.binread(entry.source_path)
            combined_data << data
            unpack_sizes << data.bytesize

            # Calculate CRC
            crc = Omnizip::Checksums::Crc32.new
            crc.update(data)
            crcs << crc.value
          end

          # Compress combined data
          packed_data = compress(combined_data)

          {
            packed_data: packed_data,
            packed_size: packed_data.bytesize,
            unpack_size: combined_data.bytesize,
            unpack_sizes: unpack_sizes,
            crcs: crcs,
          }
        end

        # Get method ID for this compression algorithm
        #
        # @return [Integer] Method ID
        def method_id
          case @algorithm
          when :copy then Constants::MethodId::COPY
          when :lzma then Constants::MethodId::LZMA
          when :lzma2 then Constants::MethodId::LZMA2
          when :ppmd, :ppmd7 then Constants::MethodId::PPMD
          when :bzip2 then Constants::MethodId::BZIP2
          else Constants::MethodId::LZMA2
          end
        end

        # Get filter IDs for filter chain
        #
        # @return [Array<Integer>] Filter IDs
        def filter_ids
          @filters.filter_map do |filter_sym|
            case filter_sym
            when :bcj_x86 then Constants::FilterId::BCJ_X86
            when :delta then Constants::FilterId::DELTA
            end
          end
        end

        # Get properties for compression algorithm
        #
        # @return [String, nil] Binary properties
        def properties
          return nil if @algorithm == :copy || @algorithm.nil?

          case @algorithm
          when :lzma2
            # LZMA2 properties: dictionary size encoded
            dict_size = 1 << (15 + @level)
            prop = 0
            prop += 1 while dict_size > (2 << prop)
            [prop].pack("C")
          when :lzma
            # LZMA properties: lc, lp, pb, dict_size
            lc = 3
            lp = 0
            pb = 2
            dict_size = 1 << (15 + @level)
            [lc + (lp * 9) + (pb * 9 * 5)].pack("C") +
              [dict_size].pack("V")
          end
        end
      end
    end
  end
end
