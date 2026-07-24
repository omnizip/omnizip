# frozen_string_literal: true

module Omnizip
  module Implementations
    # Base classes for implementation inheritance
    module Base
      autoload :LZMADecoderBase,
               "omnizip/implementations/base/lzma_decoder_base"
      autoload :LZMAEncoderBase,
               "omnizip/implementations/base/lzma_encoder_base"
      autoload :LZMA2DecoderBase,
               "omnizip/implementations/base/lzma2_decoder_base"
      autoload :LZMA2EncoderBase,
               "omnizip/implementations/base/lzma2_encoder_base"
      autoload :StateMachineBase,
               "omnizip/implementations/base/state_machine_base"
    end
  end
end
