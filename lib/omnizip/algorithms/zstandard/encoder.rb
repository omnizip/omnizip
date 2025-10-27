# frozen_string_literal: true

require_relative "constants"

begin
  require "zstd-ruby"
rescue LoadError
  # Zstd gem not available - provide helpful error message
  module Zstd
    def self.compress(*)
      raise LoadError, "Zstandard support requires the 'zstd-ruby' gem. " \
                       "Install it with: gem install zstd-ruby"
    end
  end
end

module Omnizip
  module Algorithms
    class Zstandard
      # Zstandard encoder using zstd-ruby gem
      #
      # This class wraps the zstd-ruby gem to provide Zstandard
      # compression following the established Omnizip architecture.
      class Encoder
        include Constants

        attr_reader :output_stream, :options

        # Initialize encoder
        #
        # @param output_stream [IO] Output stream for compressed data
        # @param options [Hash] Encoder options
        # @option options [Integer] :level Compression level (1-22)
        def initialize(output_stream, options = {})
          @output_stream = output_stream
          @options = options
          @level = options[:level] || DEFAULT_LEVEL
        end

        # Encode data stream
        #
        # @param data [String] Data to compress
        # @return [void]
        def encode_stream(data)
          compressed = Zstd.compress(data, @level)
          @output_stream.write(compressed)
        end
      end
    end
  end
end
