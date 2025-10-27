# frozen_string_literal: true

require "zlib"
require_relative "constants"

module Omnizip
  module Algorithms
    class Deflate
      # Deflate decoder using Zlib
      #
      # This class wraps Ruby's Zlib::Inflate to provide Deflate
      # decompression following the established Omnizip architecture.
      class Decoder
        include Constants

        attr_reader :input_stream

        # Initialize decoder
        #
        # @param input_stream [IO] Input stream of compressed data
        def initialize(input_stream)
          @input_stream = input_stream
        end

        # Decode compressed data stream
        #
        # @return [String] Decompressed data
        def decode_stream
          compressed = @input_stream.read
          inflater = Zlib::Inflate.new
          decompressed = inflater.inflate(compressed)
          inflater.close
          decompressed
        end
      end
    end
  end
end
