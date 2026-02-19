# frozen_string_literal: true

require "stringio"
require_relative "../../../../../../lib/omnizip/algorithms/lzma"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Solid
          # Solid LZMA encoder with persistent dictionary
          #
          # This encoder maintains LZMA dictionary state across multiple files,
          # allowing later files to reference data from earlier files. This is
          # the core technique behind solid compression's improved ratios.
          #
          # Unlike normal compression where each file is independent, solid
          # compression treats all files as one continuous stream, maximizing
          # dictionary-based compression efficiency.
          #
          # @example Compress multiple files in solid mode
          #   encoder = SolidEncoder.new(level: 5)
          #   compressed = encoder.compress_stream(concatenated_data)
          class SolidEncoder
            # @return [Integer] Compression level (1-5)
            attr_reader :level

            # @return [Hash] LZMA options
            attr_reader :lzma_options

            # Initialize solid encoder
            #
            # @param options [Hash] Encoder options
            # @option options [Integer] :level Compression level (1-5, default: 3)
            def initialize(options = {})
              @level = options[:level] || 3
              @lzma_options = build_lzma_options(@level)
            end

            # Compress data with persistent dictionary
            #
            # @param data [String] Data to compress (concatenated files)
            # @return [String] Compressed data
            def compress_stream(data)
              input = StringIO.new(data)
              output = StringIO.new
              output.set_encoding(Encoding::BINARY)

              # Create LZMA encoder
              lzma = Algorithms::LZMA.new

              # Compress entire stream at once (maintains dictionary)
              lzma.compress(input, output, @lzma_options)

              output.string
            end

            # Decompress solid stream
            #
            # @param data [String] Compressed data
            # @return [String] Decompressed data
            def decompress_stream(data)
              input = StringIO.new(data)
              output = StringIO.new
              output.set_encoding(Encoding::BINARY)

              lzma = Algorithms::LZMA.new
              lzma.decompress(input, output)

              output.string
            end

            # Build LZMA options for solid compression
            #
            # Solid compression benefits from larger dictionaries since
            # we're compressing more data at once.
            #
            # @param level [Integer] RAR5 compression level (1-5)
            # @return [LzmaOptions] LZMA encoder options
            def build_lzma_options(level)
              # Use larger dictionaries for solid mode
              # This allows better cross-file references
              dict_size = 1 << case level
                               when 1 then 20  # 1 MB (fastest)
                               when 2 then 22  # 4 MB (fast)
                               when 3 then 24  # 16 MB (normal)
                               when 4 then 25  # 32 MB (good)
                               when 5 then 26  # 64 MB (best)
                               else 24 # default: 16 MB
                               end

              LzmaOptions.new(level, dict_size)
            end

            # Simple options class for LZMA parameters
            class LzmaOptions
              attr_reader :level, :dict_size

              def initialize(level, dict_size)
                @level = level
                @dict_size = dict_size
              end
            end
          end
        end
      end
    end
  end
end
