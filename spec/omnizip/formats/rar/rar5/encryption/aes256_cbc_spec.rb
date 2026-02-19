# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/encryption/aes256_cbc"

RSpec.describe Omnizip::Formats::Rar::Rar5::Encryption::Aes256Cbc do
  let(:key) { SecureRandom.random_bytes(32) }
  let(:iv) { SecureRandom.random_bytes(16) }
  let(:cipher) { described_class.new(key, iv) }

  describe "#initialize" do
    it "creates cipher with valid key and IV" do
      expect(cipher.key).to eq(key)
      expect(cipher.iv).to eq(iv)
    end

    it "raises error for invalid key size" do
      wrong_key = "too short"

      expect do
        described_class.new(wrong_key, iv)
      end.to raise_error(ArgumentError, /Key must be 32 bytes/)
    end

    it "raises error for invalid IV size" do
      wrong_iv = "too short"

      expect do
        described_class.new(key, wrong_iv)
      end.to raise_error(ArgumentError, /IV must be 16 bytes/)
    end
  end

  describe "#encrypt and #decrypt" do
    it "encrypts and decrypts simple text" do
      plaintext = "Hello, World!"
      ciphertext = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(ciphertext)

      expect(decrypted).to eq(plaintext)
    end

    it "encrypts and decrypts longer text" do
      plaintext = "Lorem ipsum dolor sit amet. " * 10
      ciphertext = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(ciphertext)

      expect(decrypted).to eq(plaintext)
    end

    it "encrypts and decrypts binary data" do
      plaintext = (([0] * 50) + ([255] * 50)).pack("C*")
      ciphertext = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(ciphertext)

      expect(decrypted).to eq(plaintext)
    end

    it "encrypts and decrypts empty data" do
      plaintext = ""
      ciphertext = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(ciphertext)

      expect(decrypted).to eq(plaintext)
    end

    it "produces different ciphertext for different plaintext" do
      ciphertext1 = cipher.encrypt("data1")
      ciphertext2 = cipher.encrypt("data2")

      expect(ciphertext1).not_to eq(ciphertext2)
    end

    it "produces different ciphertext for different IVs" do
      plaintext = "Same plaintext"

      cipher1 = described_class.new(key, SecureRandom.random_bytes(16))
      cipher2 = described_class.new(key, SecureRandom.random_bytes(16))

      ciphertext1 = cipher1.encrypt(plaintext)
      ciphertext2 = cipher2.encrypt(plaintext)

      expect(ciphertext1).not_to eq(ciphertext2)
    end

    it "applies PKCS#7 padding" do
      # Text length not multiple of 16, should be padded
      plaintext = "Not aligned" # 11 bytes
      ciphertext = cipher.encrypt(plaintext)

      # With padding, should be multiple of 16
      expect(ciphertext.bytesize % 16).to eq(0)
    end

    it "handles data that is block-size aligned" do
      plaintext = "A" * 16 # Exactly one block
      ciphertext = cipher.encrypt(plaintext)
      decrypted = cipher.decrypt(ciphertext)

      expect(decrypted).to eq(plaintext)
    end
  end

  describe ".generate_iv" do
    it "generates 16-byte IV" do
      iv = described_class.generate_iv

      expect(iv).to be_a(String)
      expect(iv.bytesize).to eq(16)
      expect(iv.encoding).to eq(Encoding::BINARY)
    end

    it "generates different IVs each time" do
      iv1 = described_class.generate_iv
      iv2 = described_class.generate_iv

      expect(iv1).not_to eq(iv2)
    end
  end

  describe "security properties" do
    it "uses CBC mode (ciphertext blocks differ)" do
      plaintext = "AAAA" * 10 # Repetitive plaintext
      ciphertext = cipher.encrypt(plaintext)

      # In CBC mode, identical plaintext blocks produce different ciphertext
      # due to chaining
      blocks = ciphertext.scan(/.{16}/m)
      unique_blocks = blocks.uniq

      # Should have multiple unique blocks despite repetitive input
      expect(unique_blocks.size).to be > 1
    end
  end
end
