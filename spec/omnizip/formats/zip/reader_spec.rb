# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Zip::Reader do
  let(:test_zip_path) do
    File.join(File.dirname(__FILE__), "../../../fixtures/zip/simple.zip")
  end
  let(:reader) { described_class.new(test_zip_path) }

  describe "#initialize" do
    it "creates a new reader with file path" do
      expect(reader.file_path).to eq(test_zip_path)
      expect(reader.entries).to be_empty
    end
  end

  describe "#read" do
    context "with a simple ZIP file" do
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
  end

  describe "#list_entries" do
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
        :directory,
      )
    end
  end

  describe "#extract_all" do
    let(:output_dir) { Dir.mktmpdir }

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
