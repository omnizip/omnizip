# frozen_string_literal: true

module Omnizip
  # Compression algorithm implementations
  module Algorithms
    autoload :LZMA2Const, "omnizip/algorithms/lzma2/constants"
    autoload :LZMA, "omnizip/algorithms/lzma"
    autoload :LZMA2, "omnizip/algorithms/lzma2"
    autoload :LZMA2XzEncoderAdapter,
             "omnizip/algorithms/lzma2/xz_encoder_adapter"
    autoload :LZMA2Chunk, "omnizip/algorithms/lzma2/lzma2_chunk"
    autoload :LZMA2Encoder, "omnizip/algorithms/lzma2/encoder"
    autoload :XzUtilsDecoder, "omnizip/algorithms/lzma/xz_utils_decoder"
    autoload :PPMd7, "omnizip/algorithms/ppmd7"
    autoload :PPMd8, "omnizip/algorithms/ppmd8"
    autoload :BZip2, "omnizip/algorithms/bzip2"
    autoload :Deflate, "omnizip/algorithms/deflate"
    autoload :Deflate64, "omnizip/algorithms/deflate64"
    autoload :Zstandard, "omnizip/algorithms/zstandard"
  end
end
