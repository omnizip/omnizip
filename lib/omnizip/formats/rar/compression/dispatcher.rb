# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Compression
        # Algorithm dispatcher for RAR compression
        #
        # Selects appropriate compression algorithm based on RAR method
        # and dispatches to correct encoder/decoder.
        #
        # Responsibilities:
        # - Algorithm selection based on compression method
        # - Dispatch to appropriate decoder/encoder
        # - Error handling for unsupported/unknown methods
        #
        # Note: Does NOT perform actual compression/decompression
        # (delegated to decoder/encoder classes)
        class Dispatcher
          # RAR compression methods
          METHOD_STORE = 0x30      # No compression
          METHOD_FASTEST = 0x31    # LZ77+Huffman (fast)
          METHOD_FAST = 0x32       # LZ77+Huffman
          METHOD_NORMAL = 0x33     # LZ77+Huffman (default)
          METHOD_GOOD = 0x34       # LZ77+Huffman or PPMd
          METHOD_BEST = 0x35       # PPMd

          # Custom errors
          class UnsupportedMethodError < StandardError; end
          class DecompressionError < StandardError; end
          class CompressionError < StandardError; end

          class << self
            # Decompress data using appropriate algorithm
            #
            # @param method [Integer] RAR compression method (0x30-0x35)
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Decoder options
            # @raise [UnsupportedMethodError] if method unknown
            # @raise [DecompressionError] if decompression fails
            def decompress(method, input, output, options = {})
              case method
              when METHOD_STORE
                decompress_store(input, output)
              when METHOD_FASTEST, METHOD_FAST, METHOD_NORMAL
                decompress_lz77_huffman(input, output, options)
              when METHOD_GOOD
                decompress_good(input, output, options)
              when METHOD_BEST
                decompress_ppmd(input, output, options)
              else
                raise UnsupportedMethodError,
                      "Unknown compression method: 0x#{method.to_s(16).upcase}"
              end
            rescue StandardError => e
              unless e.is_a?(UnsupportedMethodError)
                raise DecompressionError,
                      "Decompression failed: #{e.message}"
              end

              raise
            end

            # Compress data using appropriate algorithm
            #
            # @param method [Integer] RAR compression method
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Encoder options
            # @raise [UnsupportedMethodError] if method unknown
            # @raise [CompressionError] if compression fails
            # @raise [NotImplementedError] for methods not yet implemented
            def compress(method, input, output, options = {})
              case method
              when METHOD_STORE
                compress_store(input, output)
              when METHOD_FASTEST, METHOD_FAST, METHOD_NORMAL
                compress_lz77_huffman(input, output, options)
              when METHOD_GOOD
                compress_good(input, output, options)
              when METHOD_BEST
                compress_ppmd(input, output, options)
              else
                raise UnsupportedMethodError,
                      "Unknown compression method: 0x#{method.to_s(16).upcase}"
              end
            rescue StandardError => e
              raise CompressionError, "Compression failed: #{e.message}" unless
                e.is_a?(UnsupportedMethodError) || e.is_a?(NotImplementedError)

              raise
            end

            private

            # Decompress METHOD_STORE (no compression)
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            def decompress_store(input, output)
              # Direct copy, no decompression needed
              ::IO.copy_stream(input, output)
            end

            # Decompress using LZ77+Huffman decoder
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Decoder options
            def decompress_lz77_huffman(input, output, options)
              require_relative "lz77_huffman/decoder"

              decoder = LZ77Huffman::Decoder.new(input, options)
              decoded_data = decoder.decode
              output.write(decoded_data)
            end

            # Decompress METHOD_GOOD (adaptive)
            #
            # For now, default to LZ77+Huffman
            # In future, could analyze content to choose algorithm
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Decoder options
            def decompress_good(input, output, options)
              # TODO: Implement content-based algorithm selection
              # For now, use LZ77+Huffman as default
              decompress_lz77_huffman(input, output, options)
            end

            # Decompress using PPMd decoder
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Decoder options
            def decompress_ppmd(input, output, options)
              require_relative "ppmd/decoder"

              decoder = PPMd::Decoder.new(input, options)
              decoded_data = decoder.decode_stream
              output.write(decoded_data)
            end

            # Compress METHOD_STORE (no compression)
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            def compress_store(input, output)
              # Direct copy, no compression
              ::IO.copy_stream(input, output)
            end

            # Compress using LZ77+Huffman encoder
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Encoder options
            def compress_lz77_huffman(input, output, options)
              require_relative "lz77_huffman/encoder"

              encoder = LZ77Huffman::Encoder.new(output, options)
              encoder.encode(input)
            end

            # Compress METHOD_GOOD (adaptive)
            #
            # For now, default to LZ77+Huffman
            # In future, could analyze content to choose algorithm
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Encoder options
            def compress_good(input, output, options)
              # TODO: Implement content-based algorithm selection
              # For now, use LZ77+Huffman as default
              compress_lz77_huffman(input, output, options)
            end

            # Compress using PPMd encoder
            #
            # @param input [IO] Input stream
            # @param output [IO] Output stream
            # @param options [Hash] Encoder options
            def compress_ppmd(input, output, options)
              require_relative "ppmd/encoder"

              encoder = PPMd::Encoder.new(output, options)
              encoder.encode_stream(input)
            end

            # Select decoder class for method (for testing)
            #
            # @param method [Integer] Compression method
            # @return [Class, nil] Decoder class or nil for METHOD_STORE
            def select_decoder(method)
              case method
              when METHOD_STORE
                nil
              when METHOD_FASTEST, METHOD_FAST, METHOD_NORMAL, METHOD_GOOD
                require_relative "lz77_huffman/decoder"
                LZ77Huffman::Decoder
              when METHOD_BEST
                require_relative "ppmd/decoder"
                PPMd::Decoder
              else
                raise UnsupportedMethodError,
                      "Unknown compression method: 0x#{method.to_s(16).upcase}"
              end
            end
          end
        end
      end
    end
  end
end
