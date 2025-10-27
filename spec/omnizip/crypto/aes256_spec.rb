# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Crypto::Aes256 do
  let(:password) { "my_secret_password" }
  let(:plaintext) { "Hello, AES-256 encryption!" }

  describe ".encrypt and .decrypt" do
    it "encrypts and decrypts data correctly" do
      result = described_class.encrypt(plaintext, password)

      decrypted = described_class.decrypt(
        result[:data],
        password,
        result[:salt],
        result[:iv],
        result[:cycles_power]
      )

      expect(decrypted).to eq(plaintext)
    end

    it "produces different ciphertext with different salts" do
      result1 = described_class.encrypt(plaintext, password)
      result2 = described_class.encrypt(plaintext, password)

      expect(result1[:data]).not_to eq(result2[:data])
      expect(result1[:salt]).not_to eq(result2[:salt])
    end

    it "respects custom cycles power" do
      result = described_class.encrypt(
        plaintext,
        password,
        num_cycles_power: 16
      )

      expect(result[:cycles_power]).to eq(16)

      decrypted = described_class.decrypt(
        result[:data],
        password,
        result[:salt],
        result[:iv],
        16
      )

      expect(decrypted).to eq(plaintext)
    end
  end

  describe ".generate_salt" do
    it "generates 16-byte salt by default" do
      salt = described_class.generate_salt

      expect(salt.bytesize).to eq(16)
    end

    it "generates unique salts" do
      salt1 = described_class.generate_salt
      salt2 = described_class.generate_salt

      expect(salt1).not_to eq(salt2)
    end
  end

  describe ".generate_iv" do
    it "generates 16-byte IV" do
      iv = described_class.generate_iv

      expect(iv.bytesize).to eq(16)
    end

    it "generates unique IVs" do
      iv1 = described_class.generate_iv
      iv2 = described_class.generate_iv

      expect(iv1).not_to eq(iv2)
    end
  end
end

RSpec.describe Omnizip::Crypto::Aes256::KeyDerivation do
  let(:password) { "test_password" }
  let(:salt) { "a" * 16 }

  describe ".derive_key" do
    it "derives 32-byte key" do
      key = described_class.derive_key(password, salt, 16)

      expect(key.bytesize).to eq(32)
    end

    it "produces same key for same inputs" do
      key1 = described_class.derive_key(password, salt, 16)
      key2 = described_class.derive_key(password, salt, 16)

      expect(key1).to eq(key2)
    end

    it "produces different keys for different passwords" do
      key1 = described_class.derive_key("password1", salt, 16)
      key2 = described_class.derive_key("password2", salt, 16)

      expect(key1).not_to eq(key2)
    end

    it "produces different keys for different salts" do
      key1 = described_class.derive_key(password, "a" * 16, 16)
      key2 = described_class.derive_key(password, "b" * 16, 16)

      expect(key1).not_to eq(key2)
    end

    it "raises error for invalid salt size" do
      expect do
        described_class.derive_key(password, "short", 16)
      end.to raise_error(ArgumentError, /Salt must be/)
    end

    it "raises error for empty password" do
      expect do
        described_class.derive_key("", salt, 16)
      end.to raise_error(ArgumentError, /Password cannot be empty/)
    end
  end
end

RSpec.describe Omnizip::Crypto::Aes256::Cipher do
  let(:key) { "a" * 32 }
  let(:iv) { "b" * 16 }
  let(:cipher) { described_class.new(key, iv) }
  let(:plaintext) { "Test encryption data" }

  describe "#encrypt and #decrypt" do
    it "encrypts and decrypts data correctly" do
      encrypted = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(encrypted)

      expect(decrypted).to eq(plaintext)
    end

    it "produces different ciphertext for same plaintext" do
      encrypted1 = cipher.encrypt(plaintext)
      encrypted2 = cipher.encrypt(plaintext)

      # Same cipher should produce same output
      expect(encrypted1).to eq(encrypted2)
    end

    it "handles empty data" do
      encrypted = cipher.encrypt("")
      decrypted = cipher.decrypt(encrypted)

      expect(decrypted).to eq("")
    end
  end

  describe "initialization" do
    it "raises error for invalid key size" do
      expect do
        described_class.new("short", iv)
      end.to raise_error(ArgumentError, /Key must be/)
    end

    it "raises error for invalid IV size" do
      expect do
        described_class.new(key, "short")
      end.to raise_error(ArgumentError, /IV must be/)
    end
  end
end
