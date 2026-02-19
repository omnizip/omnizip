# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Models
          # Encryption options for RAR5 archives
          #
          # This model configures password-based encryption using
          # AES-256-CBC with PBKDF2-HMAC-SHA256 key derivation.
          #
          # @example Enable encryption with default settings
          #   options = EncryptionOptions.new(
          #     enabled: true,
          #     password: "SecurePassword123"
          #   )
          #
          # @example Custom KDF iterations
          #   options = EncryptionOptions.new(
          #     enabled: true,
          #     password: "SecurePassword123",
          #     kdf_iterations: 524_288  # 2^19, higher security
          #   )
          class EncryptionOptions < Lutaml::Model::Serializable
            # Enable encryption (default: false)
            attribute :enabled, :boolean, default: false

            # Encryption password
            attribute :password, :string, default: nil

            # PBKDF2 iteration count (default: 262,144 = 2^18)
            attribute :kdf_iterations, :integer, default: 262_144

            # Validate options
            #
            # @raise [ArgumentError] If validation fails
            def validate!
              if enabled? && (password.nil? || password.empty?)
                raise ArgumentError,
                      "Password required when encryption is enabled"
              end

              if kdf_iterations < 65_536 || kdf_iterations > 1_048_576
                raise ArgumentError,
                      "KDF iterations must be between 65,536 and 1,048,576"
              end
            end

            # Check if encryption is enabled
            #
            # @return [Boolean] true if enabled
            def enabled?
              enabled == true
            end

            # Check if password is set
            #
            # @return [Boolean] true if password provided
            def has_password?
              !password.nil? && !password.empty?
            end
          end
        end
      end
    end
  end
end
