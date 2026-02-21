# frozen_string_literal: true

module Omnizip
  # Password protection module
  # Provides encryption and password validation for archives
  module Password
    autoload :PasswordValidator, "omnizip/password/password_validator"
    autoload :EncryptionStrategy, "omnizip/password/encryption_strategy"
    autoload :ZipCryptoStrategy, "omnizip/password/zip_crypto_strategy"
    autoload :WinzipAesStrategy, "omnizip/password/winzip_aes_strategy"
    autoload :EncryptionRegistry, "omnizip/password/encryption_registry"

    class << self
      # Validate a password
      # @param password [String] Password to validate
      # @param options [Hash] Validation options
      # @return [Boolean] True if valid
      def validate(password, **options)
        validator = PasswordValidator.new(**options)
        validator.validate(password)
      end

      # Check password strength
      # @param password [String] Password to check
      # @return [Symbol] Strength label (:weak, :fair, :good, :strong)
      def strength(password)
        validator = PasswordValidator.new
        validator.strength_label(password)
      end

      # Create encryption strategy
      # @param method [Symbol] Encryption method
      # @param password [String] Password
      # @param options [Hash] Strategy options
      # @return [EncryptionStrategy] Encryption strategy instance
      def create_strategy(method, password, **options)
        EncryptionRegistry.create(method, password, **options)
      end

      # Get available encryption methods
      # @return [Array<Symbol>] List of methods
      def encryption_methods
        EncryptionRegistry.strategies
      end

      # Prompt for password (with confirmation)
      # @param confirm [Boolean] Require confirmation
      # @return [String] Password entered by user
      def prompt(confirm: true)
        require "io/console"

        print "Enter password: "
        password = $stdin.noecho(&:gets).chomp
        puts

        if confirm
          print "Confirm password: "
          confirmation = $stdin.noecho(&:gets).chomp
          puts

          unless password == confirmation
            raise PasswordError, "Passwords do not match"
          end
        end

        password
      end

      # Read password from environment variable
      # @param var_name [String] Environment variable name
      # @return [String, nil] Password or nil
      def from_env(var_name = "OMNIZIP_PASSWORD")
        ENV.fetch(var_name, nil)
      end

      # Read password from file
      # @param file_path [String] Path to password file
      # @return [String] Password from file
      def from_file(file_path)
        File.read(file_path).strip
      end
    end
  end

  # Password-related error
  class PasswordError < Error; end
end
