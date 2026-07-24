# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      # Compression namespace for RAR compression algorithms
      module Compression
        autoload :BitStream, "omnizip/formats/rar/compression/bit_stream"
        autoload :Dispatcher, "omnizip/formats/rar/compression/dispatcher"

        # Subdirectory namespaces
        autoload :PPMd, "omnizip/formats/rar/compression/ppmd"
        autoload :LZ77Huffman, "omnizip/formats/rar/compression/lz77_huffman"
      end
    end
  end
end
