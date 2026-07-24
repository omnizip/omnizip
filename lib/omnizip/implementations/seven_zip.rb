# frozen_string_literal: true

module Omnizip
  module Implementations
    # 7-Zip SDK reference implementations
    module SevenZip
      autoload :LZMA, "omnizip/implementations/seven_zip/lzma"
      autoload :LZMA2, "omnizip/implementations/seven_zip/lzma2"
    end
  end
end
