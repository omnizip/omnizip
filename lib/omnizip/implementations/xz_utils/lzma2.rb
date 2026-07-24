# frozen_string_literal: true


require "omnizip"
module Omnizip
  module Implementations
    module XZUtils
      # XZ Utils LZMA2 implementation namespace
      module LZMA2
        autoload :Encoder, "omnizip/implementations/xz_utils/lzma2/encoder"
        autoload :Decoder, "omnizip/implementations/xz_utils/lzma2/decoder"
      end
    end
  end
end
