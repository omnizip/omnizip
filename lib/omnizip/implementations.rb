# frozen_string_literal: true

module Omnizip
  # Bit-level SDK ports: state machines, range coders, match finders,
  # raw LZMA/LZMA2 encoders and decoders.
  #
  # This namespace owns the *primitives*; +Omnizip::Algorithms+ owns
  # the *streaming contract*. The boundary is: +Algorithms+ calls
  # +Implementations+, never the reverse. Files under this tree
  # should never reach across into format-specific concerns (no
  # .7z header parsing, no ZIP central directory, no tar entry
  # metadata).
  #
  # The two top-level sub-namespaces mirror the upstream SDK split:
  # - +SevenZip+ : ports of 7-Zip's LZMA/LZMA2 encoder + decoder
  # - +XZUtils+ : ports of XZ Utils' LZMA/LZMA2 encoder + decoder
  #
  # Despite the LZMA name, the two SDKs diverge in subtle ways (no
  # EOS marker, different chunk padding, different property-byte
  # handling); keeping them in separate trees makes those
  # divergences visible rather than hidden in flag parameters.
  module Implementations
    autoload :Base, "omnizip/implementations/base"
  end
end
