# frozen_string_literal: true

module Omnizip
  # High-level compression algorithm facades.
  #
  # Each top-level constant in this namespace (Deflate, BZip2, LZMA,
  # LZMA2, Zstandard, PPMd7, PPMd8) is a facade that exposes the
  # streaming +.compress+/+.decompress+ contract from +Omnizip::Algorithm+.
  # Format-specific readers/writers call these facades for the actual
  # compression work; the facades themselves do not know about archive
  # container structure.
  #
  # Bit-level SDK ports (state machines, range coders, match finders)
  # live under +Omnizip::Implementations+, not here. This namespace
  # owns the *streaming contract*; that namespace owns the *primitives*.
  # The boundary is: +Algorithms+ calls +Implementations+, never the
  # reverse.
  module Algorithms
    autoload :PPMdBase, "omnizip/algorithms/ppmd_base"
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
