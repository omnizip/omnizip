# frozen_string_literal: true

require "openssl"
require_relative "constants"
require_relative "../../checksums/crc32"

module Omnizip
  module Formats
    module SevenZip
      # 7z header encryption using AES-256
      # Encrypts archive headers to hide filenames and structure
      class HeaderEncryptor
        include Constants

        # AES-256 parameters
        AES_KEY_SIZE = 32  # 256 bits
        AES_IV_SIZE = 16   # 128 bits
        SALT_SIZE = 16     # 128 bits

        # PBKDF2 parameters
        PBKDF2_ITERATIONS = 262_144 # 256K iterations for strong key derivation

        attr_reader :password, :salt, :iv

        # Initialize encryptor with password
        #
        # @param password [String] Encryption password
        def initialize(password)
          @password = password
          @salt = nil
          @iv = nil
        end

        # Encrypt header data
        #
        # @param header_data [String] Unencrypted header bytes
        # @return [Hash] Encrypted data with metadata
        #   - :data [String] Encrypted bytes
        #   - :salt [String] Salt used for key derivation
        #   - :iv [String] Initialization vector
        #   - :size [Integer] Original size before encryption
        def encrypt(header_data)
          # Generate random salt and IV
          @salt = OpenSSL::Random.random_bytes(SALT_SIZE)
          @iv = OpenSSL::Random.random_bytes(AES_IV_SIZE)

          # Derive encryption key from password
          key = derive_key(@password, @salt)

          # Encrypt data
          cipher = OpenSSL::Cipher.new("AES-256-CBC")
          cipher.encrypt
          cipher.key = key
          cipher.iv = @iv

          encrypted = cipher.update(header_data) + cipher.final

          {
            data: encrypted,
            salt: @salt,
            iv: @iv,
            size: header_data.bytesize
          }
        end

        # Decrypt header data
        #
        # @param encrypted_data [String] Encrypted bytes
        # @param salt [String] Salt used during encryption
        # @param iv [String] Initialization vector
        # @return [String] Decrypted header bytes
        # @raise [OpenSSL::Cipher::CipherError] if password is incorrect
        def decrypt(encrypted_data, salt, iv)
          # Derive decryption key from password
          key = derive_key(@password, salt)

          # Decrypt data
          decipher = OpenSSL::Cipher.new("AES-256-CBC")
          decipher.decrypt
          decipher.key = key
          decipher.iv = iv

          decipher.update(encrypted_data) + decipher.final
        rescue OpenSSL::Cipher::CipherError => e
          raise "Failed to decrypt header: incorrect password or corrupted data (#{e.message})"
        end

        # Derive encryption key from password using PBKDF2
        #
        # @param password [String] User password
        # @param salt [String] Random salt
        # @return [String] Derived key
        def derive_key(password, salt)
          OpenSSL::PKCS5.pbkdf2_hmac(
            password,
            salt,
            PBKDF2_ITERATIONS,
            AES_KEY_SIZE,
            OpenSSL::Digest.new("SHA256")
          )
        end

        # Verify password against encrypted header
        #
        # @param encrypted_data [String] Encrypted header
        # @param salt [String] Salt used
        # @param iv [String] IV used
        # @return [Boolean] true if password can decrypt
        def verify_password(encrypted_data, salt, iv)
          decrypt(encrypted_data, salt, iv)
          true
        rescue StandardError
          false
        end

        # Calculate CRC of header data
        #
        # @param data [String] Header data
        # @return [Integer] CRC32 value
        def calculate_crc(data)
          crc = Omnizip::Checksums::Crc32.new
          crc.update(data)
          crc.value
        end
      end
    end
  end
end
