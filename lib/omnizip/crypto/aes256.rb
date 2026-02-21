# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require "openssl"
require "digest/sha2"

module Omnizip
  module Crypto
    # AES-256 encryption for 7-Zip archives
    #
    # Implements 7-Zip's AES-256-CBC encryption with:
    # - Password-based key derivation (SHA-256)
    # - Configurable salt and cycles
    # - CBC mode with IV
    #
    # This follows 7-Zip's encryption specification.
    class Aes256
      autoload :Constants, "omnizip/crypto/aes256/constants"
      autoload :KeyDerivation, "omnizip/crypto/aes256/key_derivation"
      autoload :Cipher, "omnizip/crypto/aes256/cipher"
      include Constants

      # Encrypt data with AES-256
      #
      # @param data [String] Data to encrypt
      # @param password [String] Encryption password
      # @param options [Hash] Encryption options
      # @option options [Integer] :num_cycles_power Power of 2 for key
      #   derivation iterations
      # @option options [String] :salt Random salt (auto-generated if nil)
      # @option options [String] :iv Initialization vector
      #   (auto-generated if nil)
      # @return [Hash] Encrypted data with metadata
      def self.encrypt(data, password, options = {})
        salt = options[:salt] || generate_salt
        iv = options[:iv] || generate_iv
        cycles_power = options[:num_cycles_power] || DEFAULT_CYCLES_POWER

        key = KeyDerivation.derive_key(password, salt, cycles_power)
        cipher = Cipher.new(key, iv)

        encrypted_data = cipher.encrypt(data)

        {
          data: encrypted_data,
          salt: salt,
          iv: iv,
          cycles_power: cycles_power,
        }
      end

      # Decrypt data with AES-256
      #
      # @param encrypted_data [String] Encrypted data
      # @param password [String] Decryption password
      # @param salt [String] Salt used during encryption
      # @param iv [String] IV used during encryption
      # @param cycles_power [Integer] Cycles power used during encryption
      # @return [String] Decrypted data
      def self.decrypt(encrypted_data, password, salt, iv, cycles_power)
        key = KeyDerivation.derive_key(password, salt, cycles_power)
        cipher = Cipher.new(key, iv)

        cipher.decrypt(encrypted_data)
      end

      # Generate random salt
      #
      # @param size [Integer] Salt size in bytes (default 16)
      # @return [String] Random salt
      def self.generate_salt(size = SALT_SIZE)
        OpenSSL::Random.random_bytes(size)
      end

      # Generate random IV
      #
      # @return [String] Random IV
      def self.generate_iv
        OpenSSL::Random.random_bytes(IV_SIZE)
      end
    end
  end
end
