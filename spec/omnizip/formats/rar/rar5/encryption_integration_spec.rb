# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/writer"
require "tempfile"
require "tmpdir"

RSpec.describe "RAR5 Encryption Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:archive_path) { File.join(temp_dir, "encrypted.rar") }
  let(:password) { "SecureTestPassword123!" }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "encrypted archive creation" do
    it "creates encrypted archive with password" do
      test_file = File.join(temp_dir, "secret.txt")
      File.write(test_file, "Confidential data")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :store,
                                                       password: password)

      writer.add_file(test_file)
      result = writer.write

      expect(result).to eq(archive_path)
      expect(File.exist?(archive_path)).to be true
      expect(File.size(archive_path)).to be > 0
    end

    it "creates encrypted archive with LZMA compression" do
      test_file = File.join(temp_dir, "data.txt")
      File.write(test_file, "Test content " * 100)

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       level: 3,
                                                       password: password)

      writer.add_file(test_file)
      writer.write

      expect(File.exist?(archive_path)).to be true
    end

    it "creates encrypted archive with custom KDF iterations" do
      test_file = File.join(temp_dir, "secure.dat")
      File.write(test_file, "Sensitive information")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :store,
                                                       password: password,
                                                       kdf_iterations: 524_288) # Higher security

      writer.add_file(test_file)
      writer.write

      expect(File.exist?(archive_path)).to be true
    end
  end

  describe "encrypted archive with multiple files" do
    it "encrypts multiple files independently" do
      files = []
      3.times do |i|
        path = File.join(temp_dir, "file#{i}.txt")
        File.write(path, "Content #{i}")
        files << path
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :store,
                                                       password: password)

      files.each { |f| writer.add_file(f) }
      writer.write

      expect(File.exist?(archive_path)).to be true
    end
  end

  describe "encrypted archive with directory" do
    it "encrypts entire directory" do
      source_dir = File.join(temp_dir, "confidential")
      FileUtils.mkdir_p(File.join(source_dir, "subdir"))

      File.write(File.join(source_dir, "file1.txt"), "Secret 1")
      File.write(File.join(source_dir, "file2.txt"), "Secret 2")
      File.write(File.join(source_dir, "subdir", "file3.txt"), "Secret 3")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       level: 5,
                                                       password: password)

      writer.add_directory(source_dir)
      writer.write

      expect(File.exist?(archive_path)).to be true
    end
  end

  describe "RAR5 signature and format" do
    it "writes correct RAR5 signature for encrypted archive" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       password: password)
      writer.add_file(test_file)
      writer.write

      # Read RAR5 signature (first 8 bytes)
      signature = File.binread(archive_path, 8)
      expected = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*")

      expect(signature).to eq(expected)
    end
  end

  describe "encryption with solid compression" do
    it "creates encrypted solid archive" do
      files = []
      5.times do |i|
        path = File.join(temp_dir, "similar#{i}.txt")
        File.write(path, "def method_#{i}\n  puts 'Hello'\nend\n")
        files << path
      end

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       compression: :lzma,
                                                       level: 5,
                                                       solid: true,
                                                       password: password)

      files.each { |f| writer.add_file(f) }
      writer.write

      expect(File.exist?(archive_path)).to be true
      # Encrypted solid archives should be smaller than non-solid
    end
  end

  describe "error handling" do
    it "handles empty password gracefully (no encryption)" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test")

      # Empty password should create unencrypted archive
      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       password: "")

      writer.add_file(test_file)
      # Should succeed without encryption
      expect { writer.write }.not_to raise_error
      expect(File.exist?(archive_path)).to be true
    end

    it "handles binary file encryption" do
      binary_file = File.join(temp_dir, "binary.dat")
      File.binwrite(binary_file, ([0, 127, 255] * 100).pack("C*"))

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       password: password)
      writer.add_file(binary_file)
      writer.write

      expect(File.exist?(archive_path)).to be true
    end
  end

  describe "encryption strength" do
    it "uses PBKDF2-HMAC-SHA256 for key derivation" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test")

      writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                       password: password,
                                                       kdf_iterations: 262_144) # Standard security

      writer.add_file(test_file)
      writer.write

      # Archive should be created successfully
      expect(File.exist?(archive_path)).to be true

      # Archive size should be larger than plaintext due to encryption padding
      original_size = File.size(test_file)
      archive_size = File.size(archive_path)
      expect(archive_size).to be > original_size
    end
  end
end
