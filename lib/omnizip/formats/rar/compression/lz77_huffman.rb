# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Compression
        # LZ77+Huffman compression namespace for RAR
        module LZ77Huffman
          autoload :Decoder, "omnizip/formats/rar/compression/lz77_huffman/decoder"
          autoload :Encoder, "omnizip/formats/rar/compression/lz77_huffman/encoder"
          autoload :HuffmanBuilder, "omnizip/formats/rar/compression/lz77_huffman/huffman_builder"
          autoload :HuffmanCoder, "omnizip/formats/rar/compression/lz77_huffman/huffman_coder"
          autoload :MatchFinder, "omnizip/formats/rar/compression/lz77_huffman/match_finder"
          autoload :SlidingWindow, "omnizip/formats/rar/compression/lz77_huffman/sliding_window"
        end
      end
    end
  end
end
