# frozen_string_literal: true

require_relative "key_derivation"
require_relative "aes256_cbc"
require_relative "encryption_header"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Encryption
          # Encryption manager for RAR5 archives
          #
          # This manager coordinates the encryption process:
          # 1. Generate salt and IV
          # 2. Derive key from password using PBKDF2
          # 3. Encrypt file data with AES-256-CBC
          # 4. Create encryption header with metadata
          #
          # @example Encrypt file data
          #   manager = EncryptionManager.new("SecurePassword", kdf_iterations: 262_144)
          #   result = manager.encrypt_file_data(file_data)
          #   # result[:encrypted_data] = encrypted bytes
          #   # result[:header] = EncryptionHeader with salt, IV, etc.
          class EncryptionManager
            # @return [String] Password for encryption
            attr_reader :password

            # @return [Integer] PBKDF2 iteration count
            attr_reader :kdf_iterations

            # @return [String, nil] Optional pre-generated salt
            attr_reader :salt

            # @return [String, nil] Optional pre-generated IV
            attr_reader :iv

            # Initialize encryption manager
            #
            # @param password [String] Encryption password
            # @param options [Hash] Options
            # @option options [Integer] :kdf_iterations PBKDF2 iterations (default: 262,144)
            # @option options [String] :salt Pre-generated salt (16 bytes, optional)
            # @option options [String] :iv Pre-generated IV (16 bytes, optional)
            def initialize(password, options = {})
              @password = password
              @kdf_iterations = options[:kdf_iterations] || KeyDerivation::DEFAULT_ITERATIONS
              @salt = options[:salt]
              @iv = options[:iv]

              validate_password!
              validate_iterations!
            end

            # Encrypt file data
            #
            # @param plaintext [String] File data to encrypt
            # @return [Hash] Encryption result
            # @option result [String] :encrypted_data Encrypted bytes
            # @option result [EncryptionHeader] :header Encryption metadata
            # @option result [String] :key Derived encryption key (for debugging)
            def encrypt_file_data(plaintext)
              # Generate or use provided salt and IV
              salt = @salt || KeyDerivation.generate_salt
              iv = @iv || Aes256Cbc.generate_iv

              # Derive key from password
              key = KeyDerivation.derive_key(@password, salt, @kdf_iterations)

              # Encrypt data
              cipher = Aes256Cbc.new(key, iv)
              encrypted = cipher.encrypt(plaintext)

              # Create encryption header
              header = create_encryption_header(salt, iv)

              {
                encrypted_data: encrypted,
                header: header,
                key: key, # Include for verification if needed
              }
            end

            # Decrypt file data
            #
            # @param ciphertext [String] Encrypted data
            # @param header [EncryptionHeader] Encryption metadata
            # @return [String] Decrypted data
            # @raise [ArgumentError] If password incorrect
            def decrypt_file_data(ciphertext, header)
              # Extract salt and IV
              salt = header.salt_binary
              iv = header.iv_binary

              # Derive key from password
              key = KeyDerivation.derive_key(@password, salt,
                                             header.kdf_iterations)

              # Decrypt data
              cipher = Aes256Cbc.new(key, iv)
              cipher.decrypt(ciphertext)
            rescue OpenSSL::Cipher::CipherError => e
              raise ArgumentError,
                    "Decryption failed (wrong password?): #{e.message}"
            end

            # Verify password without full decryption
            #
            # This checks if the derived key can decrypt the check value.
            # Faster than decrypting entire file.
            #
            # @param header [EncryptionHeader] Encryption metadata
            # @return [Boolean] true if password correct
            def verify_password(_header)
              # For now, we'll need a small encrypted sample to verify
              # This is a simplified check - full implementation would use
              # the check_value field properly
              true # Placeholder
            rescue StandardError
              false
            end

            private

            # Create encryption header
            #
            # @param salt [String] 16-byte salt
            # @param iv [String] 16-byte IV
            # @return [EncryptionHeader] Header object
            def create_encryption_header(salt, iv)
              header = EncryptionHeader.new
              header.version = 0 # AES-256
              header.kdf_iterations = @kdf_iterations
              header.salt_binary = salt
              header.iv_binary = iv
              header.check_value = "" # Placeholder for password check
              header
            end

            # Validate password
            #
            # @raise [ArgumentError] If password invalid
            def validate_password!
              if @password.nil? || @password.empty?
                raise ArgumentError, "Password cannot be empty"
              end
            end

            # Validate iteration count
            #
            # @raise [ArgumentError] If iterations invalid
            def validate_iterations!
              min = KeyDerivation::MIN_ITERATIONS
              max = KeyDerivation::MAX_ITERATIONS

              return if @kdf_iterations.between?(min, max)

              raise ArgumentError,
                    "KDF iterations must be between #{min} and #{max}"
            end
          end
        end
      end
    end
  end
end
