# frozen_string_literal: true

module Omnizip
  module Formats
    # XZ format implementation namespace
    #
    # This module contains XZ format implementation components.
    # Classes are autoloaded for lazy loading.
    module XzImpl
      # Variable-Length Integer codec
      autoload :VLI, "omnizip/formats/xz_impl/vli"

      # XZ block header encoder
      autoload :BlockHeader, "omnizip/formats/xz_impl/block_header"

      # XZ block header parser
      autoload :BlockHeaderParser, "omnizip/formats/xz_impl/block_header_parser"

      # XZ block encoder
      autoload :BlockEncoder, "omnizip/formats/xz_impl/block_encoder"

      # XZ block decoder
      autoload :BlockDecoder, "omnizip/formats/xz_impl/block_decoder"

      # XZ index encoder
      autoload :IndexEncoder, "omnizip/formats/xz_impl/index_encoder"

      # XZ index decoder
      autoload :IndexDecoder, "omnizip/formats/xz_impl/index_decoder"

      # XZ stream header encoder
      autoload :StreamHeader, "omnizip/formats/xz_impl/stream_header"

      # XZ stream header parser
      autoload :StreamHeaderParser,
               "omnizip/formats/xz_impl/stream_header_parser"

      # XZ stream footer encoder
      autoload :StreamFooter, "omnizip/formats/xz_impl/stream_footer"

      # XZ stream footer parser
      autoload :StreamFooterParser,
               "omnizip/formats/xz_impl/stream_footer_parser"

      # XZ stream encoder
      autoload :StreamEncoder, "omnizip/formats/xz_impl/stream_encoder"

      # XZ stream decoder
      autoload :StreamDecoder, "omnizip/formats/xz_impl/stream_decoder"
    end
  end
end
