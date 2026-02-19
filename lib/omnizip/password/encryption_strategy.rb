# frozen_string_literal: true

module Omnizip
  module Password
    # Base class for encryption strategies
    # Defines the interface for encrypting/decrypting archive entries
    class EncryptionStrategy
      attr_reader :password

      # Initialize encryption strategy
      # @param password [String] Password to use
      def initialize(password)
        @password = password
        validate_password
      end

      # Encrypt data
      # @param data [String] Data to encrypt
      # @return [String] Encrypted data
      # @raise [NotImplementedError] Subclasses must implement
      def encrypt(data)
        raise NotImplementedError, "#{self.class} must implement #encrypt"
      end

      # Decrypt data
      # @param data [String] Data to decrypt
      # @return [String] Decrypted data
      # @raise [NotImplementedError] Subclasses must implement
      def decrypt(data)
        raise NotImplementedError, "#{self.class} must implement #decrypt"
      end

      # Get encryption method ID for ZIP format
      # @return [Integer] Compression method ID
      # @raise [NotImplementedError] Subclasses must implement
      def compression_method
        raise NotImplementedError,
              "#{self.class} must implement #compression_method"
      end

      # Get extra field data for ZIP header
      # @return [String] Extra field data
      def extra_field_data
        ""
      end

      # Get encryption flags for ZIP header
      # @return [Integer] Encryption flags
      def encryption_flags
        0x0001 # Bit 0: encrypted
      end

      # Check if this strategy supports the given data
      # @param data [String] Data to check
      # @return [Boolean] True if supported
      def supports?(_data)
        true
      end

      # Get encryption method name
      # @return [Symbol] Method name
      def method_name
        self.class.name.split("::").last
          .gsub(/Strategy$/, "")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end

      protected

      # Validate password
      # @raise [ArgumentError] If password is invalid
      def validate_password
        raise ArgumentError, "Password cannot be nil" if password.nil?
        raise ArgumentError, "Password cannot be empty" if password.empty?
      end

      # Derive encryption key from password
      # @param salt [String] Salt for key derivation
      # @param iterations [Integer] Number of iterations
      # @return [String] Derived key
      def derive_key(salt, iterations = 1000)
        require "openssl"
        OpenSSL::PKCS5.pbkdf2_hmac(
          password,
          salt,
          iterations,
          32, # 256 bits
          OpenSSL::Digest.new("SHA256"),
        )
      end
    end
  end
end
