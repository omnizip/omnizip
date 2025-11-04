# frozen_string_literal: true

require_relative "encryption_strategy"

module Omnizip
  module Password
    # WinZip AES encryption (recommended)
    # Implements WinZip AES-256 encryption standard
    class WinzipAesStrategy < EncryptionStrategy
      # WinZip AES compression method
      COMPRESSION_METHOD = 99 # AES encryption

      # AES key sizes
      KEY_SIZE_128 = 1
      KEY_SIZE_192 = 2
      KEY_SIZE_256 = 3

      # Extra field header IDs
      WINZIP_AES_EXTRA_ID = 0x9901

      attr_reader :key_size, :actual_compression_method

      # Initialize WinZip AES encryption
      # @param password [String] Password to use
      # @param key_size [Integer] Key size (128, 192, or 256 bits)
      # @param compression_method [Integer] Actual compression method to use
      def initialize(password, key_size: 256, compression_method: 8)
        super(password)
        @key_size = validate_key_size(key_size)
        @actual_compression_method = compression_method
      end

      # Encrypt data using WinZip AES
      # @param data [String] Data to encrypt
      # @return [String] Encrypted data with authentication
      def encrypt(data)
        require "openssl"

        # Generate salt
        salt = generate_salt

        # Derive keys
        encryption_key, password_verify, hmac_key = derive_winzip_keys(salt)

        # Create cipher
        cipher = OpenSSL::Cipher.new("AES-#{key_bits}-CTR")
        cipher.encrypt
        cipher.key = encryption_key
        cipher.iv = "\x00" * 16 # WinZip AES uses zero IV

        # Encrypt data
        encrypted = cipher.update(data) + cipher.final

        # Calculate HMAC
        hmac = calculate_hmac(hmac_key, encrypted)

        # Return: salt + password_verify + encrypted_data + hmac
        salt + password_verify + encrypted + hmac
      end

      # Decrypt data using WinZip AES
      # @param data [String] Encrypted data
      # @return [String] Decrypted data
      def decrypt(data)
        require "openssl"

        # Extract components
        salt_size = salt_length
        salt = data[0, salt_size]
        password_verify_bytes = data[salt_size, 2]
        hmac_size = 10
        encrypted_data = data[(salt_size + 2)...-hmac_size]
        stored_hmac = data[-hmac_size..-1]

        # Derive keys
        encryption_key, expected_verify, hmac_key = derive_winzip_keys(salt)

        # Verify password
        unless password_verify_bytes == expected_verify
          raise Omnizip::PasswordError, "Incorrect password"
        end

        # Verify HMAC
        calculated_hmac = calculate_hmac(hmac_key, encrypted_data)
        unless stored_hmac == calculated_hmac
          raise Omnizip::PasswordError, "Data integrity check failed"
        end

        # Decrypt data
        cipher = OpenSSL::Cipher.new("AES-#{key_bits}-CTR")
        cipher.decrypt
        cipher.key = encryption_key
        cipher.iv = "\x00" * 16

        cipher.update(encrypted_data) + cipher.final
      end

      # Get compression method for ZIP header
      # @return [Integer] Compression method ID (99 for AES)
      def compression_method
        COMPRESSION_METHOD
      end

      # Get extra field data for ZIP central directory
      # @return [String] Extra field data
      def extra_field_data
        # WinZip AES extra field format:
        # 2 bytes: extra field ID (0x9901)
        # 2 bytes: data size
        # 2 bytes: AES version (0x0001 or 0x0002)
        # 2 bytes: vendor ID (0x4145 = "AE")
        # 1 byte: AES strength (1=128, 2=192, 3=256)
        # 2 bytes: actual compression method

        data = [
          0x0002, # AES version 2
          0x4145, # Vendor ID "AE"
          key_size_code,
          actual_compression_method
        ].pack("vvCv")

        [WINZIP_AES_EXTRA_ID, data.bytesize].pack("vv") + data
      end

      # Get encryption flags
      # @return [Integer] Encryption flags
      def encryption_flags
        0x0001 | 0x0040 # Encrypted + strong encryption
      end

      private

      def key_bits
        case @key_size
        when KEY_SIZE_128 then 128
        when KEY_SIZE_192 then 192
        when KEY_SIZE_256 then 256
        end
      end

      def key_size_code
        @key_size
      end

      def salt_length
        key_bits / 16 # Salt length in bytes
      end

      def validate_key_size(size)
        case size
        when 128 then KEY_SIZE_128
        when 192 then KEY_SIZE_192
        when 256 then KEY_SIZE_256
        else
          raise ArgumentError, "Invalid key size: #{size}. Must be 128, 192, or 256"
        end
      end

      def generate_salt
        require "securerandom"
        SecureRandom.random_bytes(salt_length)
      end

      def derive_winzip_keys(salt)
        require "openssl"

        # WinZip uses PBKDF2 with HMAC-SHA1
        key_material = OpenSSL::PKCS5.pbkdf2_hmac(
          password,
          salt,
          1000, # iterations
          (2 * key_bits / 8) + 2, # key + hmac + verify
          OpenSSL::Digest::SHA1.new
        )

        key_size_bytes = key_bits / 8

        encryption_key = key_material[0, key_size_bytes]
        password_verify = key_material[key_size_bytes, 2]
        hmac_key = key_material[(key_size_bytes + 2), key_size_bytes]

        [encryption_key, password_verify, hmac_key]
      end

      def calculate_hmac(key, data)
        require "openssl"
        OpenSSL::HMAC.digest(OpenSSL::Digest::SHA1.new, key, data)[0, 10]
      end
    end
  end
end