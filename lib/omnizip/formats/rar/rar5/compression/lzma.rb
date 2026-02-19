# frozen_string_literal: true

require "stringio"
require_relative "../../../../algorithms/lzma"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Compression
          # LZMA compression method for RAR5
          #
          # This adapter uses the existing LZMA implementation with
          # RAR5-specific parameters and encoding.
          #
          # RAR5 compression methods (from spec):
          # - 0: STORE (no compression)
          # - 1: FASTEST
          # - 2: FAST
          # - 3: NORMAL
          # - 4: GOOD
          # - 5: BEST
          #
          # For methods 1-5, RAR5 uses LZMA compression with different
          # dictionary sizes and compression levels.
          #
          # @example Compress data with LZMA
          #   compressed = Lzma.compress("Hello, World!", level: 5)
          class Lzma
            # Compression method identifier for RAR5
            # Methods 1-5 all use LZMA with different parameters
            METHOD_FASTEST = 1
            METHOD_FAST = 2
            METHOD_NORMAL = 3
            METHOD_GOOD = 4
            METHOD_BEST = 5

            # Compress data using LZMA
            #
            # @param data [String] Data to compress
            # @param options [Hash] Compression options
            # @option options [Integer] :level Compression level (1-5, default: 3)
            # @return [Hash] Hash with :data (compressed) and :properties (9 bytes for extra area)
            def self.compress(data, options = {})
              level = options[:level] || METHOD_NORMAL

              # Create StringIO streams for LZMA
              input = StringIO.new(data)
              output = StringIO.new
              output.set_encoding(Encoding::BINARY)

              # Create LZMA encoder with RAR5-appropriate settings
              lzma = Algorithms::LZMA.new
              lzma_options = build_lzma_options(level)

              # Build encoder options hash that LZMA encoder will accept
              encoder_options = {
                dict_size: lzma_options.dict_size,
                lc: lzma_options.lc,
                lp: lzma_options.lp,
                pb: lzma_options.pb,
                level: level,
              }

              # Compress using LZMA with RAR5 parameters
              lzma.compress(input, output, encoder_options)

              # The LZMA encoder outputs:
              #   - 1 byte: properties (lc, lp, pb)
              #   - 4 bytes: dictionary size (little-endian)
              #   - 8 bytes: uncompressed size (little-endian)
              #   - remaining: compressed data
              #
              # RAR5 stores properties in file header extra area (type 0x03),
              # so we extract them separately
              compressed_with_header = output.string

              if compressed_with_header.bytesize > 13
                # Extract LZMA properties for RAR5 extra area
                # RAR5 stores: property byte (1) + dict size (4) = 5 bytes
                # NOT the uncompressed size (which is in the next 8 bytes of LZMA header)
                properties = compressed_with_header[0, 5]

                # Extract raw LZMA stream (skip 13-byte header)
                compressed_data = compressed_with_header[13..]

                {
                  data: compressed_data,
                  properties: properties,
                }
              else
                # Edge case: if compression produced less than 13 bytes (extremely rare),
                # return original data uncompressed with nil properties
                warn "LZMA output too small (#{compressed_with_header.bytesize} bytes), using STORE"
                {
                  data: data,
                  properties: nil,
                }
              end
            end

            # Decompress LZMA-compressed data
            #
            # @param data [String] Compressed data (raw LZMA stream without header)
            # @param options [Hash] Decompression options
            # @option options [String] :properties The 5-byte properties from compress (property byte + dict size)
            # @option options [Integer] :uncompressed_size Expected uncompressed size (optional, for EOS marker mode)
            # @return [String] Decompressed data
            def self.decompress(data, options = {})
              properties = options[:properties]
              uncompressed_size = options[:uncompressed_size]

              # Reconstruct the 13-byte LZMA header if properties are provided
              if properties && properties.bytesize >= 5
                # properties contains: 1 byte props + 4 bytes dict size
                # We need to add 8 bytes for uncompressed size
                header = properties.dup
                header += if uncompressed_size
                            # Add uncompressed size as 8-byte little-endian
                            [uncompressed_size].pack("Q<")
                          else
                            # Use -1 (0xFFFFFFFFFFFFFFFF) to indicate EOS marker mode
                            [0xFFFFFFFFFFFFFFFF].pack("Q<")
                          end
                full_data = header + data
              else
                # Assume data already has header (backward compatibility)
                full_data = data
              end

              input = StringIO.new(full_data)
              output = StringIO.new
              output.set_encoding(Encoding::BINARY)

              # Use SDK decoder since RAR5 LZMA was compressed with SDK encoder
              require_relative "../../../../implementations/seven_zip/lzma/decoder"
              decoder = Implementations::SevenZip::LZMA::Decoder.new(input)
              decoder.decode_stream(output)

              output.string
            end

            # Get compression method identifier for level
            #
            # @param level [Integer] Compression level (1-5)
            # @return [Integer] Method ID
            def self.method_id(level = METHOD_NORMAL)
              level.clamp(METHOD_FASTEST, METHOD_BEST)
            end

            # Get compression info VINT value
            #
            # For RAR5, compression_info encodes:
            # - Bits 0-5: compression method (1-5 for LZMA)
            # - Bits 6+: version (0 for now)
            #
            # @param level [Integer] Compression level (1-5)
            # @return [Integer] Compression info value
            def self.compression_info(level = METHOD_NORMAL)
              method = method_id(level)
              method & 0x3F # Bits 0-5 only
            end

            # Build LZMA options based on RAR5 compression level
            #
            # @param level [Integer] RAR5 compression level (1-5)
            # @return [LzmaOptions] LZMA encoder options object
            def self.build_lzma_options(level)
              # RAR5 compression levels map to LZMA parameters
              # These are approximations based on typical RAR behavior
              dict_size = 1 << case level
                               when 1 then 18  # 256 KB (fastest)
                               when 2 then 20  # 1 MB (fast)
                               when 3 then 22  # 4 MB (normal)
                               when 4 then 23  # 8 MB (good)
                               when 5 then 24  # 16 MB (best)
                               else 22 # default: 4 MB
                               end

              # RAR5 uses specific LZMA parameters: lc=1, lp=2, pb=0
              # (Different from standalone LZMA which typically uses lc=3, lp=0, pb=2)
              LzmaOptions.new(level, dict_size, lc: 1, lp: 2, pb: 0)
            end

            # Simple options class for LZMA parameters
            class LzmaOptions
              attr_reader :level, :dict_size, :lc, :lp, :pb

              def initialize(level, dict_size, lc: 3, lp: 0, pb: 2)
                @level = level
                @dict_size = dict_size
                @lc = lc
                @lp = lp
                @pb = pb
              end
            end
          end
        end
      end
    end
  end
end
