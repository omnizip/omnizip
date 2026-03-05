# frozen_string_literal: true

require "stringio"

require "omnizip/formats/seven_zip"
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
        include Omnizip::Formats::SevenZip::Constants

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
          decoder.decode(expected_size)
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
        # Analyzes bind pairs to determine which pack stream feeds which
        # BCJ2 input, and which coder (if any) decompresses it.
        #
        # BCJ2 has 4 inputs: main(0), call(1), jump(2), rc(3)
        # Each input is either:
        #   - Bound: fed by another coder's output (needs decompression)
        #   - Unbound: a direct pack stream (raw data, typically rc)
        #
        # @param bcj2_coder [Models::CoderInfo] BCJ2 coder
        # @param _compression_coder [Models::CoderInfo] (unused, kept for API compat)
        # @return [Hash] Stream layout specification
        def determine_stream_layout(_bcj2_coder, _compression_coder)
          # Compute composite in/out stream base indices for each coder
          in_bases = []
          out_bases = []
          in_pos = 0
          out_pos = 0
          @folder.coders.each do |coder|
            in_bases << in_pos
            out_bases << out_pos
            in_pos += coder.num_in_streams
            out_pos += coder.num_out_streams
          end

          # Find the BCJ2 coder index and its input stream base
          bcj2_idx = @folder.coders.index { |c| c.method_id == FilterId::BCJ2 }
          bcj2_in_base = in_bases[bcj2_idx]

          # BCJ2's 4 input streams: main, call, jump, rc
          bcj2_in_streams = (0...4).map { |i| bcj2_in_base + i }

          # Build bind map: in_stream -> out_stream
          bind_map = {}
          @folder.bind_pairs.each { |pair| bind_map[pair[0]] = pair[1] }

          # Build out_stream -> coder_index map
          out_to_coder = {}
          @folder.coders.each_with_index do |coder, ci|
            coder.num_out_streams.times do |j|
              out_to_coder[out_bases[ci] + j] = ci
            end
          end

          # Map unbound input streams to pack streams using pack_stream_indices
          # pack_stream_indices[i] = unbound_input_stream for pack stream i
          # This mapping is NOT necessarily sorted order!
          unbound_to_pack = {}
          @folder.pack_stream_indices.each_with_index do |input_stream, pack_idx|
            unbound_to_pack[input_stream] = pack_idx
          end

          # For each BCJ2 input, determine its source
          stream_names = %i[main call jump rc]
          layout = { type: :generic }

          bcj2_in_streams.each_with_index do |in_stream, i|
            name = stream_names[i]

            if bind_map.key?(in_stream)
              # Bound: fed by a coder's output
              source_out = bind_map[in_stream]
              source_coder_idx = out_to_coder[source_out]
              source_coder = @folder.coders[source_coder_idx]

              # Find the source coder's pack stream (its unbound input)
              source_in_base = in_bases[source_coder_idx]
              source_pack_in = (source_in_base...(source_in_base + source_coder.num_in_streams))
                .find { |s| unbound_to_pack.key?(s) }
              pack_idx = unbound_to_pack[source_pack_in]

              layout[name] = { pack_idx: pack_idx, coder: source_coder, unpack_idx: source_out }
            else
              # Unbound: direct pack stream (no decompression)
              pack_idx = unbound_to_pack[in_stream]
              layout[name] = { pack_idx: pack_idx, coder: nil }
            end
          end

          layout
        end

        # Read and decompress BCJ2 streams
        #
        # @param layout [Hash] Stream layout specification
        # @return [Hash] Decompressed stream data
        def read_bcj2_streams(layout)
          # Precompute absolute positions for each pack stream
          pack_positions = []
          pos = @pack_pos
          @pack_sizes.each do |size|
            pack_positions << pos
            pos += size
          end

          streams = {}

          %i[main call jump rc].each do |stream_name|
            spec = layout[stream_name]
            pack_idx = spec[:pack_idx]
            pack_size = @pack_sizes[pack_idx] || 0

            # Use absolute position for this pack stream
            abs_pos = pack_positions[pack_idx]
            @archive_io.seek(abs_pos)
            packed_data = @archive_io.read(pack_size)

            # Decompress if needed
            streams[stream_name] = if spec[:coder]
                                     unpack_idx = spec[:unpack_idx]
                                     unpack_size = @folder.unpack_sizes[unpack_idx] if unpack_idx
                                     decompress_stream(packed_data, spec[:coder], unpack_size)
                                   else
                                     # COPY - no decompression needed
                                     packed_data || "".b
                                   end
          end

          streams
        end

        # Decompress a single stream
        #
        # @param packed_data [String] Compressed data
        # @param coder [Models::CoderInfo] Coder specification
        # @param unpack_size [Integer, nil] Expected decompressed size
        # @return [String] Decompressed data
        def decompress_stream(packed_data, coder, unpack_size = nil)
          return packed_data if coder.nil?

          algo_sym = CoderChain.algorithm_for_method(coder.method_id)
          return packed_data unless algo_sym

          algo_class = Omnizip::AlgorithmRegistry.get(algo_sym)
          raise "Algorithm not found: #{algo_sym}" unless algo_class

          # Build decoder options
          options = build_decoder_options(coder, algo_sym)

          # Decompress
          input_io = StringIO.new(packed_data)
          output_io = StringIO.new
          output_io.set_encoding("BINARY")

          decoder = algo_class.new(options)

          # Use provided unpack size or estimate
          unpack_size ||= packed_data.bytesize * 10

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
