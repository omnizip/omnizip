# frozen_string_literal: true

module Omnizip
  module Formats
    # Standalone RAR5 reader/writer tree (see Formats::Rar for the
    # primary RAR support). Classes under this namespace load lazily;
    # require "omnizip" first so sibling namespaces resolve.
    module Rar5
      autoload :Compressor, "omnizip/formats/rar5/compressor"
      autoload :Decompressor, "omnizip/formats/rar5/decompressor"
      autoload :Reader, "omnizip/formats/rar5/reader"
      autoload :Writer, "omnizip/formats/rar5/writer"
    end
  end
end
