# frozen_string_literal: true

module Omnizip
  module Implementations
    module SevenZip
      # 7-Zip LZMA implementation namespace
      module LZMA
        autoload :MatchFinder,
                 "omnizip/implementations/seven_zip/lzma/match_finder"
        autoload :RangeDecoder,
                 "omnizip/implementations/seven_zip/lzma/range_decoder"
        autoload :RangeEncoder,
                 "omnizip/implementations/seven_zip/lzma/range_encoder"
        autoload :StateMachine,
                 "omnizip/implementations/seven_zip/lzma/state_machine"
        autoload :Decoder, "omnizip/implementations/seven_zip/lzma/decoder"
        autoload :Encoder, "omnizip/implementations/seven_zip/lzma/encoder"
      end
    end
  end
end
