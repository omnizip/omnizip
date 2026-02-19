# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

require "openssl"
require_relative "constants"

module Omnizip
  module Crypto
    class Aes256
      # AES-256-CBC cipher operations
      #
      # Wraps OpenSSL's AES-256-CBC implementation with proper
      # padding and error handling for 7-Zip compatibility.
      class Cipher
        include Constants

        attr_reader :key, :iv

        # Initialize cipher with key and IV
        #
        # @param key [String] 32-byte AES-256 key
        # @param iv [String] 16-byte initialization vector
        def initialize(key, iv)
          validate_key_iv(key, iv)
          @key = key
          @iv = iv
        end

        # Encrypt data using AES-256-CBC
        #
        # @param plaintext [String] Data to encrypt
        # @return [String] Encrypted data
        def encrypt(plaintext)
          cipher = create_cipher(:encrypt)

          # Handle empty data - just call final() for padding
          if plaintext.empty?
            return cipher.final
          end

          result = cipher.update(plaintext)
          result << cipher.final

          result
        end

        # Decrypt data using AES-256-CBC
        #
        # @param ciphertext [String] Encrypted data
        # @return [String] Decrypted data
        def decrypt(ciphertext)
          cipher = create_cipher(:decrypt)

          # Handle empty or very small ciphertext
          if ciphertext.empty?
            return ""
          end

          result = cipher.update(ciphertext)
          result << cipher.final

          result
        end

        private

        # Validate key and IV parameters
        #
        # @param key [String] Key to validate
        # @param iv [String] IV to validate
        # @return [void]
        # @raise [ArgumentError] If key or IV invalid
        def validate_key_iv(key, iv)
          if key.bytesize != KEY_SIZE
            raise ArgumentError,
                  "Key must be #{KEY_SIZE} bytes"
          end
          return unless iv.bytesize != IV_SIZE

          raise ArgumentError,
                "IV must be #{IV_SIZE} bytes"
        end

        # Create OpenSSL cipher instance
        #
        # @param mode [Symbol] :encrypt or :decrypt
        # @return [OpenSSL::Cipher] Configured cipher
        def create_cipher(mode)
          cipher = OpenSSL::Cipher.new("AES-256-CBC")
          cipher.send(mode)  # Call encrypt or decrypt first
          cipher.key = @key  # Then set key
          cipher.iv = @iv    # Then set IV
          cipher.padding = 1 # PKCS7 padding
          cipher
        end
      end
    end
  end
end
