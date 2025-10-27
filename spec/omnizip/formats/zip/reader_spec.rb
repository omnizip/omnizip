# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Zip::Reader do
  let(:test_zip_path) { File.join(File.dirname(__FILE__), "../../../fixtures/zip/simple.zip") }
  let(:reader) { described_class.new(test_zip_path) }

  describe "#initialize" do
    it "creates a new reader with file path" do
      expect(reader.file_path).to eq(test_zip_path)
      expect(reader.entries).to be_empty
    end
  end

  describe "#read" do
    context "with a simple ZIP file" do
      before do
        skip "Test fixture not yet created"
      end

      it "reads the archive structure" do
        reader.read
        expect(reader.entries).not_to be_empty
      end

      it "parses file entries correctly" do
        reader.read
        entry = reader.entries.first
        expect(entry).to be_a(Omnizip::Formats::Zip::CentralDirectoryHeader)
        expect(entry.filename).to be_a(String)
        expect(entry.compressed_size).to be >= 0
        expect(entry.uncompressed_size).to be >= 0
      end
    end

    context "with invalid file" do
      let(:test_zip_path) { "/tmp/nonexistent.zip" }

      it "raises an error" do
        expect { reader.read }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "#list_entries" do
    before do
      skip "Test fixture not yet created"
    end

    it "returns array of entry information" do
      reader.read
      entries = reader.list_entries
      expect(entries).to be_an(Array)
      expect(entries.first).to include(
        :filename,
        :compressed_size,
        :uncompressed_size,
        :compression_method,
        :crc32,
        :directory
      )
    end
  end

  describe "#extract_all" do
    let(:output_dir) { Dir.mktmpdir }

    before do
      skip "Test fixture not yet created"
    end

    after do
      FileUtils.rm_rf(output_dir)
    end

    it "extracts all files to output directory" do
      reader.read
      reader.extract_all(output_dir)
      expect(Dir.exist?(output_dir)).to be true
    end
  end
end