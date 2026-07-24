# frozen_string_literal: true


require "omnizip"
module Omnizip
  module Implementations
    # XZ Utils reference implementations
    module XZUtils
      autoload :LZMA2, "omnizip/implementations/xz_utils/lzma2"
    end
  end
end
