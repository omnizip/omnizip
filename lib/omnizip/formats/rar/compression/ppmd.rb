# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Compression
        # PPMd compression namespace for RAR
        module PPMd
          autoload :Context, "omnizip/formats/rar/compression/ppmd/context"
          autoload :Decoder, "omnizip/formats/rar/compression/ppmd/decoder"
          autoload :Encoder, "omnizip/formats/rar/compression/ppmd/encoder"
        end
      end
    end
  end
end
