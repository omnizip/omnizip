# frozen_string_literal: true

require_relative "encryption_strategy"

module Omnizip
  module Password
    # Traditional ZIP encryption (PKWARE)
    # WARNING: This is a weak encryption method and should not be used
    # for sensitive data. Use WinZipAesStrategy instead.
    class ZipCryptoStrategy < EncryptionStrategy
      # ZIP compression method for traditional encryption
      COMPRESSION_METHOD = 0 # Stored (encryption is separate)

      # Initialize ZIP crypto encryption
      # @param password [String] Password to use
      # @param warn_weak [Boolean] Show security warning (default: true)
      def initialize(password, warn_weak: true)
        super(password)

        if warn_weak
          warn "WARNING: Traditional ZIP encryption is weak and easily cracked."
          warn "Consider using WinZip AES encryption instead for better security."
        end
      end

      # Encrypt data using traditional ZIP encryption
      # @param data [String] Data to encrypt
      # @return [String] Encrypted data
      def encrypt(data)
        keys = initialize_keys
        encrypted = data.bytes.map do |byte|
          temp = decrypt_byte(keys)
          update_keys(keys, byte)
          byte ^ temp
        end

        # Prepend encryption header
        header = generate_encryption_header(keys)
        (header + encrypted).pack("C*")
      end

      # Decrypt data using traditional ZIP encryption
      # @param data [String] Data to decrypt
      # @return [String] Decrypted data
      def decrypt(data)
        bytes = data.bytes
        keys = initialize_keys

        # Skip encryption header (12 bytes)
        header = bytes[0...12]
        encrypted_data = bytes[12..-1]

        # Verify header
        header.each { |byte| update_keys(keys, decrypt_byte(keys) ^ byte) }

        # Decrypt data
        decrypted = encrypted_data.map do |byte|
          temp = decrypt_byte(keys)
          plaintext_byte = byte ^ temp
          update_keys(keys, plaintext_byte)
          plaintext_byte
        end

        decrypted.pack("C*")
      end

      # Get compression method for ZIP header
      # @return [Integer] Compression method ID
      def compression_method
        COMPRESSION_METHOD
      end

      # Get encryption flags
      # @return [Integer] Encryption flags (bit 0 set)
      def encryption_flags
        0x0001 # Traditional encryption
      end

      private

      # Initialize encryption keys
      # @return [Array<Integer>] Initial key values
      def initialize_keys
        keys = [0x12345678, 0x23456789, 0x34567890]

        password.each_byte do |byte|
          update_keys(keys, byte)
        end

        keys
      end

      # Update encryption keys
      # @param keys [Array<Integer>] Current keys
      # @param byte [Integer] Byte to incorporate
      def update_keys(keys, byte)
        keys[0] = crc32_update(keys[0], byte)
        keys[1] = ((keys[1] + (keys[0] & 0xFF)) * 134_775_813 + 1) & 0xFFFFFFFF
        keys[2] = crc32_update(keys[2], keys[1] >> 24)
      end

      # Decrypt a single byte
      # @param keys [Array<Integer>] Current keys
      # @return [Integer] Decrypted byte value
      def decrypt_byte(keys)
        temp = keys[2] | 2
        ((temp * (temp ^ 1)) >> 8) & 0xFF
      end

      # CRC32 update for key generation
      # @param crc [Integer] Current CRC value
      # @param byte [Integer] Byte to add
      # @return [Integer] Updated CRC
      def crc32_update(crc, byte)
        require_relative "../checksums/crc32"
        crc32 = Omnizip::Checksums::Crc32.new
        crc32.instance_variable_set(:@crc, crc)
        crc32.update(byte.chr)
        crc32.value
      end

      # Generate encryption header
      # @param keys [Array<Integer>] Encryption keys
      # @return [Array<Integer>] 12-byte header
      def generate_encryption_header(keys)
        header = Array.new(12) { rand(256) }
        header.map { |byte| decrypt_byte(keys).tap { update_keys(keys, byte) } ^ byte }
      end
    end
  end
end