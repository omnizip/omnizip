# frozen_string_literal: true

require "securerandom"
require_relative "../../../../crypto/aes256/cipher"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Encryption
          # AES-256-CBC cipher for RAR5 encryption
          #
          # Wrapper around the existing Crypto::Aes256::Cipher that provides
          # RAR5-specific encryption/decryption with proper key and IV handling.
          #
          # RAR5 uses:
          # - AES-256 in CBC mode
          # - PKCS#7 padding
          # - Per-file IV generation
          # - PBKDF2-HMAC-SHA256 key derivation
          #
          # @example Encrypt file data
          #   cipher = Aes256Cbc.new(key, iv)
          #   encrypted = cipher.encrypt(data)
          class Aes256Cbc
            # IV size (16 bytes = AES block size)
            IV_SIZE = 16

            # Key size (32 bytes for AES-256)
            KEY_SIZE = 32

            # @return [String] AES-256 key (32 bytes)
            attr_reader :key

            # @return [String] Initialization vector (16 bytes)
            attr_reader :iv

            # Initialize cipher with key and IV
            #
            # @param key [String] 32-byte AES-256 key
            # @param iv [String] 16-byte initialization vector
            # @raise [ArgumentError] If key or IV wrong size
            def initialize(key, iv)
              validate_key_iv(key, iv)
              @key = key
              @iv = iv
              @cipher = Crypto::Aes256::Cipher.new(key, iv)
            end

            # Encrypt data
            #
            # @param plaintext [String] Data to encrypt
            # @return [String] Encrypted data (with PKCS#7 padding)
            def encrypt(plaintext)
              @cipher.encrypt(plaintext)
            end

            # Decrypt data
            #
            # @param ciphertext [String] Encrypted data
            # @return [String] Decrypted data (padding removed)
            def decrypt(ciphertext)
              @cipher.decrypt(ciphertext)
            end

            # Generate random IV
            #
            # @return [String] 16-byte random IV
            def self.generate_iv
              SecureRandom.random_bytes(IV_SIZE)
            end

            private

            # Validate key and IV sizes
            #
            # @param key [String] Key to validate
            # @param iv [String] IV to validate
            # @return [void]
            # @raise [ArgumentError] If key or IV wrong size
            def validate_key_iv(key, iv)
              if key.bytesize != KEY_SIZE
                raise ArgumentError,
                      "Key must be #{KEY_SIZE} bytes, got #{key.bytesize}"
              end

              return unless iv.bytesize != IV_SIZE

              raise ArgumentError,
                    "IV must be #{IV_SIZE} bytes, got #{iv.bytesize}"
            end
          end
        end
      end
    end
  end
end
