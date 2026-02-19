# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/encryption/key_derivation"

RSpec.describe Omnizip::Formats::Rar::Rar5::Encryption::KeyDerivation do
  describe ".derive_key" do
    let(:password) { "TestPassword123" }
    let(:salt) { SecureRandom.random_bytes(16) }
    let(:iterations) { 262_144 }

    it "derives 32-byte key from password" do
      key = described_class.derive_key(password, salt, iterations)

      expect(key).to be_a(String)
      expect(key.bytesize).to eq(32)
      expect(key.encoding).to eq(Encoding::BINARY)
    end

    it "produces different keys for different passwords" do
      key1 = described_class.derive_key("password1", salt, iterations)
      key2 = described_class.derive_key("password2", salt, iterations)

      expect(key1).not_to eq(key2)
    end

    it "produces different keys for different salts" do
      salt1 = SecureRandom.random_bytes(16)
      salt2 = SecureRandom.random_bytes(16)

      key1 = described_class.derive_key(password, salt1, iterations)
      key2 = described_class.derive_key(password, salt2, iterations)

      expect(key1).not_to eq(key2)
    end

    it "produces different keys for different iteration counts" do
      key1 = described_class.derive_key(password, salt, 65_536)
      key2 = described_class.derive_key(password, salt, 262_144)

      expect(key1).not_to eq(key2)
    end

    it "produces same key for same inputs (deterministic)" do
      key1 = described_class.derive_key(password, salt, iterations)
      key2 = described_class.derive_key(password, salt, iterations)

      expect(key1).to eq(key2)
    end

    it "uses default iterations when not specified" do
      key = described_class.derive_key(password, salt)

      expect(key.bytesize).to eq(32)
    end

    it "raises error for empty password" do
      expect do
        described_class.derive_key("", salt, iterations)
      end.to raise_error(ArgumentError, /Password cannot be empty/)
    end

    it "raises error for nil password" do
      expect do
        described_class.derive_key(nil, salt, iterations)
      end.to raise_error(ArgumentError, /Password cannot be empty/)
    end

    it "raises error for wrong salt size" do
      wrong_salt = "too short"

      expect do
        described_class.derive_key(password, wrong_salt, iterations)
      end.to raise_error(ArgumentError, /Salt must be 16 bytes/)
    end

    it "raises error for iterations too low" do
      expect do
        described_class.derive_key(password, salt, 1000)
      end.to raise_error(ArgumentError, /Iterations must be between/)
    end

    it "raises error for iterations too high" do
      expect do
        described_class.derive_key(password, salt, 2_000_000)
      end.to raise_error(ArgumentError, /Iterations must be between/)
    end
  end

  describe ".generate_salt" do
    it "generates 16-byte salt" do
      salt = described_class.generate_salt

      expect(salt).to be_a(String)
      expect(salt.bytesize).to eq(16)
      expect(salt.encoding).to eq(Encoding::BINARY)
    end

    it "generates different salts each time" do
      salt1 = described_class.generate_salt
      salt2 = described_class.generate_salt

      expect(salt1).not_to eq(salt2)
    end
  end
end
