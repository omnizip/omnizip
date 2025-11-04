# frozen_string_literal: true

require "zlib"
require_relative "../rar/rar_format_base"
require_relative "../../error"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 compressor
      #
      # Compresses data using RAR v5 compression algorithms.
      # This implementation uses DEFLATE as a compatible fallback
      # for demonstration purposes. Full RAR5 compression requires
      # proprietary algorithms.
      #
      # @example Compressing data
      #   compressor = Rar5::Compressor.new
      #   compressed = compressor.compress("Hello, World!", method: :normal)
      class Compressor < Rar::RarFormatBase
        # Initialize a RAR v5 compressor
        def initialize
          super("rar5")
        end

        # Compress data using RAR v5 methods
        #
        # @param data [String] The data to compress
        # @param method [Symbol] The compression method
        # @param options [Hash] Compression options
        # @return [String] The compressed data
        def compress(data, method: :normal, **_options)
          case method
          when :store
            compress_store(data)
          when :fastest
            compress_deflate(data, level: Zlib::BEST_SPEED)
          when :fast
            compress_deflate(data, level: 3)
          when :normal
            compress_deflate(data, level: Zlib::DEFAULT_COMPRESSION)
          when :good
            compress_deflate(data, level: 7)
          when :best
            compress_deflate(data, level: Zlib::BEST_COMPRESSION)
          else
            raise FormatError,
                  "Unsupported compression method: #{method}"
          end
        end

        private

        # Store data without compression
        #
        # @param data [String] The data to store
        # @return [String] The uncompressed data
        def compress_store(data)
          data
        end

        # Compress using DEFLATE (compatible fallback)
        #
        # @param data [String] The data to compress
        # @param level [Integer] The compression level
        # @return [String] The compressed data
        def compress_deflate(data, level:)
          Zlib::Deflate.deflate(data, level)
        end
      end
    end
  end
end
