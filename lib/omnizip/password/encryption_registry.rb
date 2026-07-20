# frozen_string_literal: true

module Omnizip
  module Password
    class EncryptionRegistry < Omnizip::Registry
      class << self
        def not_found_error_class
          Omnizip::UnknownEncryptionStrategyError
        end

        def label
          "Encryption strategy"
        end

        def create(name, password, **options)
          get(name).new(password, **options)
        end
      end
    end
  end
end

Omnizip::Password::EncryptionRegistry.register(:traditional, Omnizip::Password::ZipCryptoStrategy)
Omnizip::Password::EncryptionRegistry.register(:zip_crypto, Omnizip::Password::ZipCryptoStrategy)
Omnizip::Password::EncryptionRegistry.register(:winzip_aes, Omnizip::Password::WinzipAesStrategy)
Omnizip::Password::EncryptionRegistry.register(:aes256, Omnizip::Password::WinzipAesStrategy)
