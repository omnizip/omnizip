# frozen_string_literal: true

module Omnizip
  module Formats
    # Standalone RAR3 reader/writer tree (see Formats::Rar for the
    # primary RAR support). Classes under this namespace load lazily;
    # require "omnizip" first so sibling namespaces resolve.
    module Rar3
      autoload :Compressor, "omnizip/formats/rar3/compressor"
      autoload :Decompressor, "omnizip/formats/rar3/decompressor"
      autoload :Reader, "omnizip/formats/rar3/reader"
      autoload :Writer, "omnizip/formats/rar3/writer"
    end
  end
end
