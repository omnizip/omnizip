# frozen_string_literal: true

require "spec_helper"
require "omnizip/password"

RSpec.describe Omnizip::Password do
  describe ".validate" do
    it "validates a strong password" do
      expect(described_class.validate("MySecurePass123!")).to be true
    end

    it "validates with custom requirements" do
      expect do
        described_class.validate("weak", min_length: 12)
      end.to raise_error(ArgumentError, /too short/)
    end
  end

  describe ".strength" do
    it "returns weak for short passwords" do
      expect(described_class.strength("abc")).to eq(:weak)
    end

    it "returns strong for complex passwords" do
      expect(described_class.strength("MyVeryStrong123!Pass")).to eq(:strong)
    end
  end

  describe ".encryption_methods" do
    it "returns available encryption methods" do
      methods = described_class.encryption_methods
      expect(methods).to include(:winzip_aes, :traditional)
    end
  end

  describe Omnizip::Password::PasswordValidator do
    subject { described_class.new }

    describe "#validate" do
      it "accepts valid passwords" do
        expect(subject.validate("password123")).to be true
      end

      it "rejects nil passwords" do
        expect { subject.validate(nil) }.to raise_error(ArgumentError, /cannot be nil/)
      end

      it "rejects empty passwords" do
        expect { subject.validate("") }.to raise_error(ArgumentError, /cannot be empty/)
      end

      it "rejects too short passwords" do
        validator = described_class.new(min_length: 12)
        expect { validator.validate("short") }.to raise_error(ArgumentError, /too short/)
      end
    end

    describe "#strength" do
      it "scores simple passwords low" do
        expect(subject.strength("abc")).to be < 30
      end

      it "scores complex passwords high" do
        expect(subject.strength("MyComplex123!Pass")).to be > 75
      end
    end

    describe "#strength_label" do
      it "labels weak passwords" do
        expect(subject.strength_label("abc")).to eq(:weak)
      end

      it "labels strong passwords" do
        expect(subject.strength_label("MyVerySecure123!Password")).to eq(:strong)
      end
    end

    describe "#valid?" do
      it "returns true for valid passwords" do
        expect(subject.valid?("password123")).to be true
      end

      it "returns false for invalid passwords" do
        validator = described_class.new(min_length: 20)
        expect(validator.valid?("short")).to be false
      end
    end
  end

  describe Omnizip::Password::EncryptionStrategy do
    let(:password) { "test_password" }

    it "cannot be instantiated directly" do
      strategy = described_class.new(password)
      expect { strategy.encrypt("data") }.to raise_error(NotImplementedError)
    end

    it "validates password" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /cannot be nil/)
      expect { described_class.new("") }.to raise_error(ArgumentError, /cannot be empty/)
    end
  end

  describe Omnizip::Password::ZipCryptoStrategy do
    let(:password) { "test_password" }
    subject { described_class.new(password, warn_weak: false) }

    it "encrypts and decrypts data" do
      original = "Hello, World!"
      encrypted = subject.encrypt(original)
      decrypted = subject.decrypt(encrypted)

      expect(decrypted).to eq(original)
    end

    it "produces different output for same input" do
      data = "test data"
      encrypted1 = subject.encrypt(data)
      encrypted2 = subject.encrypt(data)

      # Due to random header, encrypted data should differ
      expect(encrypted1).not_to eq(encrypted2)
    end

    it "returns correct compression method" do
      expect(subject.compression_method).to eq(0)
    end

    it "sets encryption flags" do
      expect(subject.encryption_flags).to eq(0x0001)
    end
  end

  describe Omnizip::Password::WinzipAesStrategy do
    let(:password) { "secure_password" }
    subject { described_class.new(password) }

    it "encrypts and decrypts data" do
      original = "Sensitive data that needs encryption"
      encrypted = subject.encrypt(original)
      decrypted = subject.decrypt(encrypted)

      expect(decrypted).to eq(original)
    end

    it "supports different key sizes" do
      strategy128 = described_class.new(password, key_size: 128)
      strategy256 = described_class.new(password, key_size: 256)

      data = "test"
      expect(strategy128.encrypt(data).length).not_to eq(strategy256.encrypt(data).length)
    end

    it "rejects invalid key sizes" do
      expect do
        described_class.new(password, key_size: 512)
      end.to raise_error(ArgumentError, /Invalid key size/)
    end

    it "returns correct compression method" do
      expect(subject.compression_method).to eq(99)
    end

    it "generates extra field data" do
      extra = subject.extra_field_data
      expect(extra).not_to be_empty
      expect(extra.length).to be > 8
    end

    it "fails with wrong password" do
      encrypted = subject.encrypt("secret data")
      wrong_strategy = described_class.new("wrong_password")

      expect do
        wrong_strategy.decrypt(encrypted)
      end.to raise_error(Omnizip::PasswordError, /Incorrect password/)
    end
  end

  describe Omnizip::Password::EncryptionRegistry do
    it "registers strategies" do
      expect(described_class.registered?(:winzip_aes)).to be true
      expect(described_class.registered?(:traditional)).to be true
    end

    it "retrieves registered strategies" do
      strategy_class = described_class.get(:winzip_aes)
      expect(strategy_class).to eq(Omnizip::Password::WinzipAesStrategy)
    end

    it "raises for unknown strategies" do
      expect do
        described_class.get(:unknown)
      end.to raise_error(ArgumentError, /Unknown encryption strategy/)
    end

    it "creates strategy instances" do
      strategy = described_class.create(:winzip_aes, "password")
      expect(strategy).to be_a(Omnizip::Password::WinzipAesStrategy)
    end

    it "lists all strategies" do
      strategies = described_class.strategies
      expect(strategies).to include(:winzip_aes, :traditional, :zip_crypto, :aes256)
    end
  end
end