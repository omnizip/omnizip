# frozen_string_literal: true


require "omnizip"
module Omnizip
  module Implementations
    module SevenZip
      module LZMA2
        # 7-Zip SDK LZMA2 implementation namespace
        autoload :Encoder, "omnizip/implementations/seven_zip/lzma2/encoder"
      end
    end
  end
end
