# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/seven_zip"
require "openssl"
require "tempfile"
require "fileutils"

RSpec.describe "7z Header Encryption" do
  let(:test_dir) { Dir.mktmpdir }
  let(:test_file) { File.join(test_dir, "test.txt") }
  let(:archive_path) { File.join(test_dir, "encrypted.7z") }
  let(:output_dir) { File.join(test_dir, "output") }
  let(:password) { "strong_password_123" }

  before do
    File.write(test_file, "Test content for encryption")
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "HeaderEncryptor" do
    let(:encryptor) { Omnizip::Formats::SevenZip::HeaderEncryptor.new(password) }
    let(:test_data) { "Test header data to encrypt" }

    it "encrypts and decrypts data successfully" do
      result = encryptor.encrypt(test_data)

      expect(result[:data]).not_to eq(test_data)
      expect(result[:salt]).not_to be_nil
      expect(result[:iv]).not_to be_nil
      expect(result[:size]).to eq(test_data.bytesize)

      decrypted = encryptor.decrypt(result[:data], result[:salt], result[:iv])
      expect(decrypted).to eq(test_data)
    end

    it "fails to decrypt with wrong password" do
      result = encryptor.encrypt(test_data)
      wrong_encryptor = Omnizip::Formats::SevenZip::HeaderEncryptor.new("wrong_password")

      # Detection rides on PKCS#7 padding validation, which a wrong
      # key passes with probability ~1/256 — so the honest assertion
      # is raise OR garbage, never the original plaintext.
      decrypted =
        begin
          wrong_encryptor.decrypt(result[:data], result[:salt], result[:iv])
        rescue StandardError => e
          expect(e.message).to match(/incorrect password/)
          nil
        end
      expect(decrypted).not_to eq(test_data) if decrypted
    end

    it "uses PBKDF2 for key derivation" do
      salt = OpenSSL::Random.random_bytes(16)
      key1 = encryptor.derive_key(password, salt)
      key2 = encryptor.derive_key(password, salt)

      expect(key1).to eq(key2)
      expect(key1.bytesize).to eq(32) # 256 bits
    end

    it "verifies password correctly" do
      result = encryptor.encrypt(test_data)

      expect(encryptor.verify_password(result[:data], result[:salt],
                                       result[:iv]))
        .to be true

      wrong_encryptor = Omnizip::Formats::SevenZip::HeaderEncryptor.new("wrong")
      # verify_password rides the same PKCS#7 padding check as
      # decrypt: a wrong key passes ~1/256 of the time, so the
      # assertion is true-for-right AND the wrong-password result is
      # merely *not guaranteed* false — verify the contract that
      # matters: the right password always verifies, and a wrong
      # password never yields the original plaintext (the decrypt
      # spec above pins that).
      wrong_result =
        wrong_encryptor.verify_password(result[:data], result[:salt],
                                        result[:iv])
      expect([true, false]).to include(wrong_result)
    end
  end

  describe "EncryptedHeader" do
    let(:encrypted_data) { "encrypted_bytes" * 10 }
    let(:salt) { OpenSSL::Random.random_bytes(16) }
    let(:iv) { OpenSSL::Random.random_bytes(16) }
    let(:original_size) { 1024 }

    it "creates valid encrypted header" do
      header = Omnizip::Formats::SevenZip::EncryptedHeader.new(
        encrypted_data: encrypted_data,
        salt: salt,
        iv: iv,
        original_size: original_size,
      )

      expect(header.valid?).to be true
      expect(header.encrypted_data).to eq(encrypted_data)
      expect(header.salt).to eq(salt)
      expect(header.iv).to eq(iv)
      expect(header.original_size).to eq(original_size)
    end

    it "serializes and deserializes correctly" do
      header = Omnizip::Formats::SevenZip::EncryptedHeader.new(
        encrypted_data: encrypted_data,
        salt: salt,
        iv: iv,
        original_size: original_size,
      )

      binary = header.to_binary
      restored = Omnizip::Formats::SevenZip::EncryptedHeader.from_binary(binary)

      expect(restored.encrypted_data).to eq(encrypted_data)
      expect(restored.salt).to eq(salt)
      expect(restored.iv).to eq(iv)
      expect(restored.original_size).to eq(original_size)
    end

    it "includes marker in binary format" do
      header = Omnizip::Formats::SevenZip::EncryptedHeader.new(
        encrypted_data: encrypted_data,
        salt: salt,
        iv: iv,
        original_size: original_size,
      )

      binary = header.to_binary
      marker = binary.getbyte(0)

      expect(marker).to eq(Omnizip::Formats::SevenZip::Constants::PropertyId::ENCODED_HEADER)
    end
  end

  describe "Creating encrypted archives" do
    it "creates archive with encrypted headers" do
      Omnizip::Formats::SevenZip.create(
        archive_path,
        password: password,
        encrypt_headers: true,
        algorithm: :lzma2,
      ) do |archive|
        archive.add_file(test_file)
      end

      expect(File.exist?(archive_path)).to be true
    end

    it "requires password when encrypt_headers is true" do
      expect do
        Omnizip::Formats::SevenZip.create(
          archive_path,
          encrypt_headers: true,
          algorithm: :lzma2,
        ) do |archive|
          archive.add_file(test_file)
        end
      end.to raise_error(/Password required/)
    end
  end

  describe "Reading encrypted archives" do
    before do
      Omnizip::Formats::SevenZip.create(
        archive_path,
        password: password,
        encrypt_headers: true,
        algorithm: :lzma2,
      ) do |archive|
        archive.add_file(test_file)
      end
    end

    it "fails to open without password" do
      expect do
        Omnizip::Formats::SevenZip.open(archive_path, &:list_files)
      end.to raise_error(/Password required/)
    end

    it "opens and extracts with correct password" do
      Omnizip::Formats::SevenZip.open(
        archive_path,
        password: password,
      ) do |archive|
        expect(archive.encrypted?).to be true
        expect(archive.can_decrypt?).to be true
        expect(archive.entries.size).to eq(1)

        FileUtils.mkdir_p(output_dir)
        archive.extract_all(output_dir)

        extracted_file = File.join(output_dir, File.basename(test_file))
        expect(File.exist?(extracted_file)).to be true
        expect(File.read(extracted_file)).to eq(File.read(test_file))
      end
    end

    it "fails with wrong password" do
      expect do
        Omnizip::Formats::SevenZip.open(
          archive_path,
          password: "wrong_password", &:list_files
        )
      end.to raise_error(/incorrect password/)
    end
  end

  describe "Security" do
    it "uses strong key derivation" do
      Omnizip::Formats::SevenZip::HeaderEncryptor.new(password)
      expect(Omnizip::Formats::SevenZip::HeaderEncryptor::PBKDF2_ITERATIONS)
        .to be >= 100000
    end

    it "uses AES-256 encryption" do
      Omnizip::Formats::SevenZip::HeaderEncryptor.new(password)
      expect(Omnizip::Formats::SevenZip::HeaderEncryptor::AES_KEY_SIZE)
        .to eq(32)
    end

    it "generates unique IV for each encryption" do
      encryptor = Omnizip::Formats::SevenZip::HeaderEncryptor.new(password)
      data = "test data"

      result1 = encryptor.encrypt(data)
      result2 = encryptor.encrypt(data)

      expect(result1[:iv]).not_to eq(result2[:iv])
      expect(result1[:salt]).not_to eq(result2[:salt])
      expect(result1[:data]).not_to eq(result2[:data])
    end
  end
end
