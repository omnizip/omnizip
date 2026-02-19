# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/encryption/encryption_manager"

RSpec.describe Omnizip::Formats::Rar::Rar5::Encryption::EncryptionManager do
  let(:password) { "SecurePassword123" }
  let(:manager) { described_class.new(password) }

  describe "#initialize" do
    it "creates manager with password" do
      expect(manager.password).to eq(password)
      expect(manager.kdf_iterations).to eq(262_144)
    end

    it "accepts custom KDF iterations" do
      manager = described_class.new(password, kdf_iterations: 524_288)
      expect(manager.kdf_iterations).to eq(524_288)
    end

    it "raises error for empty password" do
      expect do
        described_class.new("")
      end.to raise_error(ArgumentError, /Password cannot be empty/)
    end

    it "raises error for invalid iterations" do
      expect do
        described_class.new(password, kdf_iterations: 1000)
      end.to raise_error(ArgumentError, /KDF iterations must be between/)
    end
  end

  describe "#encrypt_file_data and #decrypt_file_data" do
    let(:plaintext) { "This is confidential file data" }

    it "encrypts and decrypts file data" do
      result = manager.encrypt_file_data(plaintext)
      header = result[:header]
      ciphertext = result[:encrypted_data]

      decrypted = manager.decrypt_file_data(ciphertext, header)

      expect(decrypted).to eq(plaintext)
    end

    it "returns encryption result with required keys" do
      result = manager.encrypt_file_data(plaintext)

      expect(result).to have_key(:encrypted_data)
      expect(result).to have_key(:header)
      expect(result).to have_key(:key)
    end

    it "creates encryption header with metadata" do
      result = manager.encrypt_file_data(plaintext)
      header = result[:header]

      expect(header.version).to eq(0)
      expect(header.kdf_iterations).to eq(262_144)
      expect(header.salt_binary.bytesize).to eq(16)
      expect(header.iv_binary.bytesize).to eq(16)
    end

    it "produces different ciphertext each time (random IV)" do
      result1 = manager.encrypt_file_data(plaintext)
      result2 = manager.encrypt_file_data(plaintext)

      expect(result1[:encrypted_data]).not_to eq(result2[:encrypted_data])
    end

    it "handles binary data" do
      binary_data = ([0, 127, 255] * 100).pack("C*")

      result = manager.encrypt_file_data(binary_data)
      decrypted = manager.decrypt_file_data(result[:encrypted_data],
                                            result[:header])

      expect(decrypted).to eq(binary_data)
    end

    it "handles empty data" do
      empty_data = ""

      result = manager.encrypt_file_data(empty_data)
      decrypted = manager.decrypt_file_data(result[:encrypted_data],
                                            result[:header])

      expect(decrypted).to eq(empty_data)
    end

    it "handles large data" do
      large_data = "A" * 100_000

      result = manager.encrypt_file_data(large_data)
      decrypted = manager.decrypt_file_data(result[:encrypted_data],
                                            result[:header])

      expect(decrypted).to eq(large_data)
    end

    it "raises error for wrong password" do
      result = manager.encrypt_file_data(plaintext)
      wrong_manager = described_class.new("WrongPassword")

      expect do
        wrong_manager.decrypt_file_data(result[:encrypted_data],
                                        result[:header])
      end.to raise_error(ArgumentError, /Decryption failed/)
    end
  end

  describe "with pre-generated salt and IV" do
    let(:salt) { SecureRandom.random_bytes(16) }
    let(:iv) { SecureRandom.random_bytes(16) }

    it "uses provided salt and IV" do
      manager = described_class.new(password, salt: salt, iv: iv)
      result = manager.encrypt_file_data("data")

      expect(result[:header].salt_binary).to eq(salt)
      expect(result[:header].iv_binary).to eq(iv)
    end

    it "produces deterministic encryption with same salt/IV" do
      plaintext = "Test data"

      manager1 = described_class.new(password, salt: salt, iv: iv)
      manager2 = described_class.new(password, salt: salt, iv: iv)

      result1 = manager1.encrypt_file_data(plaintext)
      result2 = manager2.encrypt_file_data(plaintext)

      # Same password, salt, and IV should produce same ciphertext
      expect(result1[:encrypted_data]).to eq(result2[:encrypted_data])
    end
  end

  describe "encryption with different iteration counts" do
    it "derives different keys for different iteration counts" do
      salt = SecureRandom.random_bytes(16)
      iv = SecureRandom.random_bytes(16)
      plaintext = "Test data"

      manager1 = described_class.new(password, kdf_iterations: 65_536,
                                               salt: salt, iv: iv)
      manager2 = described_class.new(password, kdf_iterations: 262_144,
                                               salt: salt, iv: iv)

      result1 = manager1.encrypt_file_data(plaintext)
      result2 = manager2.encrypt_file_data(plaintext)

      # Different iterations -> different keys -> different ciphertext
      expect(result1[:encrypted_data]).not_to eq(result2[:encrypted_data])
    end
  end
end
