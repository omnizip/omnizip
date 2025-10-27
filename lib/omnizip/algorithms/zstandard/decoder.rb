# frozen_string_literal: true

require_relative "constants"

begin
  require "zstd-ruby"
rescue LoadError
  # Zstd gem not available - provide helpful error message
  module Zstd
    def self.decompress(*)
      raise LoadError, "Zstandard support requires the 'zstd-ruby' gem. " \
                       "Install it with: gem install zstd-ruby"
    end
  end
end

module Omnizip
  module Algorithms
    class Zstandard
      # Zstandard decoder using zstd-ruby gem
      #
      # This class wraps the zstd-ruby gem to provide Zstandard
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
          Zstd.decompress(compressed)
        end
      end
    end
  end
end
