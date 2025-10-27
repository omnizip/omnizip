# frozen_string_literal: true

require "zlib"
require_relative "constants"

module Omnizip
  module Algorithms
    class Deflate
      # Deflate encoder using Zlib
      #
      # This class wraps Ruby's Zlib::Deflate to provide Deflate
      # compression following the established Omnizip architecture.
      class Encoder
        include Constants

        attr_reader :output_stream, :options

        # Initialize encoder
        #
        # @param output_stream [IO] Output stream for compressed data
        # @param options [Hash] Encoder options
        # @option options [Integer] :level Compression level (0-9)
        # @option options [Integer] :strategy Compression strategy
        # @option options [Integer] :window_bits Window size (8-15)
        def initialize(output_stream, options = {})
          @output_stream = output_stream
          @options = options
          @level = options[:level] || DEFAULT_COMPRESSION
          @strategy = options[:strategy] || DEFAULT_STRATEGY
          @window_bits = options[:window_bits] || 15
        end

        # Encode data stream
        #
        # @param data [String] Data to compress
        # @return [void]
        def encode_stream(data)
          deflater = Zlib::Deflate.new(@level, @window_bits, 9, @strategy)
          compressed = deflater.deflate(data, Zlib::FINISH)
          deflater.close
          @output_stream.write(compressed)
        end
      end
    end
  end
end
