# frozen_string_literal: true

require_relative "coder_chain"
require_relative "../../filters/bcj2/stream_data"
require_relative "../../filters/bcj2/decoder"
require "stringio"

module Omnizip
  module Formats
    module SevenZip
      # Decompresses BCJ2 multi-stream folders
      #
      # BCJ2 archives have 4 separate pack streams that need to be:
      # 1. Read separately
      # 2. Decompressed individually (main is LZMA, others are usually COPY)
      # 3. Combined via BCJ2 decoder
      class Bcj2StreamDecompressor
        include Constants

        # Initialize BCJ2 decompressor
        #
        # @param archive_io [IO] Archive file handle
        # @param folder [Models::Folder] Folder with BCJ2 coder
        # @param pack_pos [Integer] Base position of packed data
        # @param pack_sizes [Array<Integer>] Sizes of each pack stream
        # @param stream_info [Models::StreamInfo] Stream info for unpack sizes
        def initialize(archive_io, folder, pack_pos, pack_sizes, stream_info)
          @archive_io = archive_io
          @folder = folder
          @pack_pos = pack_pos
          @pack_sizes = pack_sizes
          @stream_info = stream_info
        end

        # Check if a folder contains BCJ2 coder
        #
        # @param folder [Models::Folder] Folder to check
        # @return [Boolean] true if folder has BCJ2
        def self.bcj2_folder?(folder)
          folder.coders.any? { |c| c.method_id == FilterId::BCJ2 }
        end

        # Decompress BCJ2 multi-stream folder
        #
        # @param expected_size [Integer] Expected final output size
        # @return [String] Decompressed and BCJ2-decoded data
        def decompress(expected_size)
          # Find BCJ2 coder and compression coder
          bcj2_coder = @folder.coders.find { |c| c.method_id == FilterId::BCJ2 }
          compression_coder = find_compression_coder

          raise "BCJ2 coder not found" unless bcj2_coder

          # Determine stream layout based on folder structure
          # BCJ2 has 4 input streams: main, call, jump, rc
          stream_layout = determine_stream_layout(bcj2_coder, compression_coder)

          # Read and decompress each of the 4 streams
          streams = read_bcj2_streams(stream_layout)

          # Apply BCJ2 decoder
          bcj2_data = Omnizip::Filters::Bcj2StreamData.new
          bcj2_data.main = streams[:main]
          bcj2_data.call = streams[:call]
          bcj2_data.jump = streams[:jump]
          bcj2_data.rc = streams[:rc]

          decoder = Omnizip::Filters::Bcj2Decoder.new(bcj2_data)
          result = decoder.decode

          # Truncate to expected size if needed
          result.bytesize > expected_size ? result[0, expected_size] : result
        end

        private

        # Find the compression coder (LZMA/LZMA2/etc) in the folder
        #
        # @return [Models::CoderInfo, nil] Compression coder
        def find_compression_coder
          @folder.coders.find do |c|
            [MethodId::LZMA, MethodId::LZMA2, MethodId::BZIP2,
             MethodId::DEFLATE, MethodId::DEFLATE64, MethodId::PPMD].include?(c.method_id)
          end
        end

        # Determine how streams are laid out based on folder structure
        #
        # BCJ2 folders can have different layouts:
        # Type 0 (7z default): numInStreams=5, numOutStreams=2
        #   - Coder 0: LZMA (1 in, 1 out)
        #   - Coder 1: BCJ2 (4 in, 1 out)
        #   - Pack streams: [main_lzma, call, jump, rc]
        #
        # @param bcj2_coder [Models::CoderInfo] BCJ2 coder
        # @param compression_coder [Models::CoderInfo] Compression coder
        # @return [Hash] Stream layout specification
        def determine_stream_layout(_bcj2_coder, compression_coder)
          num_in = @folder.num_in_streams
          num_out = @folder.num_out_streams
          num_pack = @pack_sizes.size

          # Type 0: 7z default (5 in, 2 out, 4 pack)
          if num_in == 5 && num_out == 2 && num_pack == 4
            {
              type: :type0,
              main: { pack_idx: 0, coder: compression_coder },
              call: { pack_idx: 1, coder: nil },  # Usually COPY
              jump: { pack_idx: 2, coder: nil },  # Usually COPY
              rc: { pack_idx: 3, coder: nil },    # Usually COPY
            }
          # Type 1: 7zr style (7 in, 4 out, 4 pack)
          elsif num_in == 7 && num_out == 4 && num_pack == 4
            # More complex layout - need to analyze bind pairs
            determine_type1_layout(compression_coder)
          else
            raise "Unsupported BCJ2 folder layout: in=#{num_in}, out=#{num_out}, pack=#{num_pack}"
          end
        end

        # Determine Type 1 layout (7zr style with separate compression per stream)
        #
        # @param compression_coder [Models::CoderInfo] Compression coder
        # @return [Hash] Stream layout
        def determine_type1_layout(compression_coder)
          # In Type 1, each stream may have its own compression
          # This is more complex and needs bind pair analysis
          # For now, assume main is compressed, others are COPY
          {
            type: :type1,
            main: { pack_idx: 0, coder: compression_coder },
            call: { pack_idx: 1, coder: nil },
            jump: { pack_idx: 2, coder: nil },
            rc: { pack_idx: 3, coder: nil },
          }
        end

        # Read and decompress BCJ2 streams
        #
        # @param layout [Hash] Stream layout specification
        # @return [Hash] Decompressed stream data
        def read_bcj2_streams(layout)
          streams = {}
          offset = 0

          %i[main call jump rc].each_with_index do |stream_name, idx|
            spec = layout[stream_name]
            pack_idx = spec[:pack_idx]
            pack_size = @pack_sizes[pack_idx] || 0

            # Calculate absolute position
            pos = @pack_pos + offset

            # Read pack data
            @archive_io.seek(pos)
            packed_data = @archive_io.read(pack_size)

            # Decompress if needed
            streams[stream_name] = if spec[:coder]
                                     decompress_stream(packed_data, spec[:coder], idx)
                                   else
                                     # COPY - no decompression needed
                                     packed_data || "".b
                                   end

            offset += pack_size
          end

          streams
        end

        # Decompress a single stream
        #
        # @param packed_data [String] Compressed data
        # @param coder [Models::CoderInfo] Coder specification
        # @param stream_idx [Integer] Stream index for unpack size lookup
        # @return [String] Decompressed data
        def decompress_stream(packed_data, coder, stream_idx)
          return packed_data if coder.nil?

          algo_sym = CoderChain.algorithm_for_method(coder.method_id)
          return packed_data unless algo_sym

          algo_class = AlgorithmRegistry.get(algo_sym)
          raise "Algorithm not found: #{algo_sym}" unless algo_class

          # Build decoder options
          options = build_decoder_options(coder, algo_sym)

          # Decompress
          input_io = StringIO.new(packed_data)
          output_io = StringIO.new
          output_io.set_encoding("BINARY")

          decoder = algo_class.new(options)

          # Get unpack size for this stream
          unpack_size = @folder.unpack_sizes[stream_idx] || (packed_data.bytesize * 10)

          decoder.decompress(input_io, output_io, size: unpack_size)
          output_io.string
        end

        # Build decoder options from coder properties
        #
        # @param coder [Models::CoderInfo] Coder with properties
        # @param algo_sym [Symbol] Algorithm symbol
        # @return [Hash] Decoder options
        def build_decoder_options(coder, algo_sym)
          options = {}
          properties = coder.properties

          return options if properties.nil? || properties.empty?

          case algo_sym
          when :lzma2
            prop_byte = properties.getbyte(0)
            dict_size = Omnizip::Algorithms::LZMA2::Properties.decode_dict_size(prop_byte)
            options[:raw_mode] = true
            options[:dict_size] = dict_size
          when :lzma
            if properties.bytesize >= 5
              props_byte = properties.getbyte(0)
              dict_size = properties[1, 4].unpack1("V")
              options[:lzma2_mode] = true
              options[:lc] = props_byte % 9
              remainder = props_byte / 9
              options[:lp] = remainder % 5
              options[:pb] = remainder / 5
              options[:dict_size] = dict_size
            end
          end

          options
        end
      end
    end
  end
end
