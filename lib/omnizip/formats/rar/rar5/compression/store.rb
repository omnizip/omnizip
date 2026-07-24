# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Compression
          # STORE compression method (uncompressed)
          #
          # This is the simplest compression method - it stores data without
          # any compression. The "compressed" size equals the original size.
          #
          # @example Compress data
          #   compressed = Store.compress("Hello, World!")
          #   compressed # => "Hello, World!"
          class Store
            # Compression method identifier
            METHOD = 0

            # Compress data (passthrough for STORE)
            #
            # @param data [String] Data to compress
            # @param _options [Hash] Options (ignored for STORE)
            # @return [String] Uncompressed data
            def self.compress(data, _options = {})
              data
            end

            # Decompress data (passthrough for STORE)
            #
            # @param data [String] Data to decompress
            # @param _options [Hash] Options (ignored for STORE)
            # @return [String] Original data
            def self.decompress(data, _options = {})
              data
            end

            # Get compression method identifier
            #
            # @return [Integer] Method ID (0 for STORE)
            def self.method_id
              METHOD
            end

            # Get compression info VINT value
            #
            # For STORE, this is just the method ID (0)
            # Bits 0-5: method (0=STORE)
            # Bits 6+: version (0 for STORE)
            #
            # @return [Integer] Compression info value
            def self.compression_info
              METHOD
            end
          end
        end
      end
    end
  end
end
