# frozen_string_literal: true

require "openssl"
require "securerandom"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Encryption
          # RAR5 password-based key derivation
          #
          # RAR5 uses PBKDF2-HMAC-SHA256 for key derivation, which is more
          # secure than 7-Zip's iterative SHA-256 approach.
          #
          # The process:
          # 1. Generate random salt (16 bytes)
          # 2. Apply PBKDF2-HMAC-SHA256 with configurable iterations
          # 3. Derive 32-byte AES-256 key
          #
          # @example Derive key from password
          #   salt = SecureRandom.random_bytes(16)
          #   key = KeyDerivation.derive_key("password", salt, 262_144)
          class KeyDerivation
            # Default PBKDF2 iterations (262,144 = 2^18)
            # This provides good security while maintaining reasonable performance
            DEFAULT_ITERATIONS = 262_144

            # Minimum iterations (2^16 = 65,536)
            MIN_ITERATIONS = 65_536

            # Maximum iterations (2^20 = 1,048,576)
            MAX_ITERATIONS = 1_048_576

            # Salt size (16 bytes)
            SALT_SIZE = 16

            # Key size (32 bytes for AES-256)
            KEY_SIZE = 32

            # Derive AES-256 key from password using PBKDF2-HMAC-SHA256
            #
            # @param password [String] User password
            # @param salt [String] Random salt (16 bytes)
            # @param iterations [Integer] Number of PBKDF2 iterations
            # @return [String] 32-byte AES-256 key
            # @raise [ArgumentError] If password empty or salt wrong size
            def self.derive_key(password, salt, iterations = DEFAULT_ITERATIONS)
              validate_inputs(password, salt, iterations)

              # PBKDF2-HMAC-SHA256
              OpenSSL::PKCS5.pbkdf2_hmac(
                password,
                salt,
                iterations,
                KEY_SIZE,
                OpenSSL::Digest.new("SHA256"),
              )
            end

            # Generate random salt
            #
            # @return [String] 16-byte random salt
            def self.generate_salt
              SecureRandom.random_bytes(SALT_SIZE)
            end

            # Validate key derivation inputs
            #
            # @param password [String] Password to validate
            # @param salt [String] Salt to validate
            # @param iterations [Integer] Iteration count to validate
            # @return [void]
            # @raise [ArgumentError] If inputs are invalid
            def self.validate_inputs(password, salt, iterations)
              if password.nil? || password.empty?
                raise ArgumentError, "Password cannot be empty"
              end

              if salt.bytesize != SALT_SIZE
                raise ArgumentError,
                      "Salt must be #{SALT_SIZE} bytes, got #{salt.bytesize}"
              end

              return if iterations.between?(MIN_ITERATIONS, MAX_ITERATIONS)

              raise ArgumentError,
                    "Iterations must be between #{MIN_ITERATIONS} and #{MAX_ITERATIONS}"
            end

            private_class_method :validate_inputs
          end
        end
      end
    end
  end
end
