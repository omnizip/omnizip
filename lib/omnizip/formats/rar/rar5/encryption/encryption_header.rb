# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require "base64"

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Encryption
          # RAR5 encryption header
          #
          # This model stores encryption parameters needed for password verification
          # and decryption. The header is written at the beginning of encrypted
          # archive sections.
          #
          # RAR5 encryption header contains:
          # - Version (always 0 for AES-256)
          # - KDF iteration count
          # - Salt for key derivation
          # - IV for AES-CBC
          # - Check value for password verification
          #
          # @example Create encryption header
          #   header = EncryptionHeader.new(
          #     version: 0,
          #     kdf_iterations: 262_144,
          #     salt: salt,
          #     iv: iv,
          #     check_value: check
          #   )
          class EncryptionHeader < Lutaml::Model::Serializable
            # Encryption version (0 for AES-256)
            attribute :version, :integer, default: 0

            # PBKDF2 iteration count
            attribute :kdf_iterations, :integer, default: 262_144

            # Salt for key derivation (16 bytes, base64 encoded for serialization)
            attribute :salt, :string

            # Initialization vector (16 bytes, base64 encoded for serialization)
            attribute :iv, :string

            # Password check value (first 8 bytes of encrypted data)
            # Used to verify password before full decryption
            attribute :check_value, :string

            # Validate header
            #
            # @raise [ArgumentError] If validation fails
            def validate!
              if version != 0
                raise ArgumentError, "Only AES-256 (version 0) is supported"
              end

              if kdf_iterations < 65_536 || kdf_iterations > 1_048_576
                raise ArgumentError,
                      "KDF iterations must be between 65,536 and 1,048,576"
              end

              # Validate salt (base64 decoded should be 16 bytes)
              decoded_salt = Base64.strict_decode64(salt)
              if decoded_salt.bytesize != 16
                raise ArgumentError, "Salt must be 16 bytes"
              end

              # Validate IV (base64 decoded should be 16 bytes)
              decoded_iv = Base64.strict_decode64(iv)
              if decoded_iv.bytesize != 16
                raise ArgumentError, "IV must be 16 bytes"
              end
            rescue ArgumentError => e
              raise ArgumentError, "Invalid encryption header: #{e.message}"
            end

            # Get salt as binary
            #
            # @return [String] 16-byte binary salt
            def salt_binary
              Base64.strict_decode64(salt)
            end

            # Get IV as binary
            #
            # @return [String] 16-byte binary IV
            def iv_binary
              Base64.strict_decode64(iv)
            end

            # Set salt from binary
            #
            # @param binary_salt [String] 16-byte binary salt
            def salt_binary=(binary_salt)
              self.salt = Base64.strict_encode64(binary_salt)
            end

            # Set IV from binary
            #
            # @param binary_iv [String] 16-byte binary IV
            def iv_binary=(binary_iv)
              self.iv = Base64.strict_encode64(binary_iv)
            end
          end
        end
      end
    end
  end
end
