# frozen_string_literal: true

module Omnizip
  # Checksum implementations
  module Checksums
    autoload :CrcBase, "omnizip/checksums/crc_base"
    autoload :Crc32, "omnizip/checksums/crc32"
    autoload :Crc64, "omnizip/checksums/crc64"
    autoload :Verifier, "omnizip/checksums/verifier"
  end
end
