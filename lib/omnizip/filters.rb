# frozen_string_literal: true

module Omnizip
  # Filter implementations for preprocessing data before compression
  module Filters
    autoload :FilterBase, "omnizip/filters/filter_base"
    autoload :BCJ, "omnizip/filters/bcj"
    autoload :BcjX86, "omnizip/filters/bcj_x86"
    autoload :Bcj2, "omnizip/filters/bcj2"
    autoload :Bcj2Constants, "omnizip/filters/bcj2/constants"
    autoload :Bcj2StreamData, "omnizip/filters/bcj2/stream_data"
    autoload :Bcj2Decoder, "omnizip/filters/bcj2/decoder"
    autoload :Bcj2Encoder, "omnizip/filters/bcj2/encoder"
    autoload :BcjArm, "omnizip/filters/bcj_arm"
    autoload :BcjArm64, "omnizip/filters/bcj_arm64"
    autoload :BcjPpc, "omnizip/filters/bcj_ppc"
    autoload :BcjSparc, "omnizip/filters/bcj_sparc"
    autoload :BcjIa64, "omnizip/filters/bcj_ia64"
    autoload :Delta, "omnizip/filters/delta"
    autoload :Registry, "omnizip/filters/registry"
  end
end
