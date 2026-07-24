# frozen_string_literal: true


require "omnizip"
module Omnizip
  # Cryptographic utilities module
  #
  # Provides encryption and decryption capabilities for archive formats
  # that support password protection.
  module Crypto
    autoload :Aes256, "omnizip/crypto/aes256"
  end
end
