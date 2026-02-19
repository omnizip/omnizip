# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/seven_zip/reader"
require "omnizip/formats/seven_zip/writer"
require "fileutils"
require "tempfile"

RSpec.describe "7-Zip Reference Files" do
  let(:reference_dir) { File.expand_path("../../../fixtures/seven_zip/reference", __dir__) }

  describe "LZMA compressed archives" do
    %w[lzma_mx1 lzma_mx5 lzma_mx9].each do |name|
      it "decompresses #{name}.7z" do
        file_path = File.join(reference_dir, "#{name}.7z")

        reader = Omnizip::Formats::SevenZip::Reader.new(file_path)
        reader.open

        expect(reader.valid?).to be true
        files = reader.list_files
        expect(files.size).to be >= 1

        # Extract and verify content
        extract_dir = Dir.mktmpdir
        reader.extract_all(extract_dir)

        extracted_file = File.join(extract_dir, "test.txt")
        expect(File.exist?(extracted_file)).to be true
        expect(File.read(extracted_file)).to include("Hello, 7-Zip")

        FileUtils.rm_rf(extract_dir)
      end
    end
  end

  describe "LZMA2 compressed archives" do
    %w[lzma2_mx1 lzma2_mx5 lzma2_mx9].each do |name|
      it "decompresses #{name}.7z" do
        file_path = File.join(reference_dir, "#{name}.7z")

        reader = Omnizip::Formats::SevenZip::Reader.new(file_path)
        reader.open

        expect(reader.valid?).to be true
        files = reader.list_files
        expect(files.size).to be >= 1

        # Extract and verify content
        extract_dir = Dir.mktmpdir
        reader.extract_all(extract_dir)

        extracted_file = File.join(extract_dir, "test.txt")
        expect(File.exist?(extracted_file)).to be true

        FileUtils.rm_rf(extract_dir)
      end
    end
  end

  describe "multi-file archives" do
    it "decompresses lzma2_multi.7z" do
      file_path = File.join(reference_dir, "lzma2_multi.7z")

      reader = Omnizip::Formats::SevenZip::Reader.new(file_path)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(2)

      # Extract and verify
      extract_dir = Dir.mktmpdir
      reader.extract_all(extract_dir)

      expect(File.exist?(File.join(extract_dir, "test.txt"))).to be true
      expect(File.exist?(File.join(extract_dir, "binary.bin"))).to be true

      FileUtils.rm_rf(extract_dir)
    end
  end

  describe "round-trip compatibility" do
    it "creates archives that 7z can extract" do
      skip "7zz not available" unless system("which 7zz > /dev/null 2>&1")

      # Create test file
      test_content = "Test content for round-trip verification! " * 50
      test_file = File.join(Dir.mktmpdir, "roundtrip_test.txt")
      File.write(test_file, test_content)

      # Create archive with Omnizip
      archive_path = File.join(Dir.mktmpdir, "omnizip_created.7z")
      writer = Omnizip::Formats::SevenZip::Writer.new(archive_path)
      writer.add_file(test_file)
      writer.write

      # Extract with official 7z
      extract_dir = Dir.mktmpdir
      result = system("7zz x -o#{extract_dir} -y #{archive_path} > /dev/null 2>&1")

      expect(result).to be true

      # Verify content
      extracted_file = File.join(extract_dir, File.basename(test_file))
      expect(File.exist?(extracted_file)).to be true
      expect(File.read(extracted_file)).to eq(test_content)

      FileUtils.rm_rf(File.dirname(test_file))
      FileUtils.rm_rf(File.dirname(archive_path))
      FileUtils.rm_rf(extract_dir)
    end
  end
end
