# frozen_string_literal: true

require "zlib"
require_relative "../rar/rar_format_base"
require_relative "../../error"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 decompressor
      #
      # Decompresses data using RAR v5 decompression algorithms.
      # This implementation uses DEFLATE as a compatible fallback
      # for demonstration purposes. Full RAR5 decompression requires
      # proprietary algorithms.
      #
      # @example Decompressing data
      #   decompressor = Rar5::Decompressor.new
      #   original = decompressor.decompress(compressed, method: :normal)
      class Decompressor < Rar::RarFormatBase
        # Initialize a RAR v5 decompressor
        def initialize
          super("rar5")
        end

        # Decompress data using RAR v5 methods
        #
        # @param data [String] The compressed data
        # @param method [Symbol] The compression method
        # @param options [Hash] Decompression options
        # @return [String] The decompressed data
        def decompress(data, method: :normal, **_options)
          case method
          when :store
            decompress_store(data)
          when :fastest, :fast, :normal, :good, :best
            decompress_deflate(data)
          else
            raise FormatError,
                  "Unsupported decompression method: #{method}"
          end
        end

        private

        # Return stored data without decompression
        #
        # @param data [String] The stored data
        # @return [String] The uncompressed data
        def decompress_store(data)
          data
        end

        # Decompress using DEFLATE (compatible fallback)
        #
        # @param data [String] The compressed data
        # @return [String] The decompressed data
        def decompress_deflate(data)
          Zlib::Inflate.inflate(data)
        rescue Zlib::Error => e
          raise FormatError, "Decompression failed: #{e.message}"
        end
      end
    end
  end
end
