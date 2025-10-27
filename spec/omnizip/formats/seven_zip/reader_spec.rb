# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::SevenZip::Reader do
  let(:fixtures_dir) do
    File.join(__dir__, "../../../fixtures/seven_zip")
  end

  describe "#initialize" do
    it "creates reader with file path" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture)
      expect(reader.file_path).to eq(fixture)
    end
  end

  describe "#open" do
    it "opens and parses .7z archive" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
      expect(reader.header).not_to be_nil
    end

    it "parses LZMA compressed archive" do
      fixture = File.join(fixtures_dir, "simple_lzma.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
    end

    it "parses LZMA2 compressed archive" do
      fixture = File.join(fixtures_dir, "simple_lzma2.7z")
      reader = described_class.new(fixture)
      reader.open

      expect(reader).to be_valid
    end
  end

  describe "#list_files" do
    it "lists files in archive" do
      fixture = File.join(fixtures_dir, "simple_copy.7z")
      reader = described_class.new(fixture).open

      files = reader.list_files
      expect(files).to be_an(Array)
      expect(files).not_to be_empty
    end
  end

  describe "format registry" do
    it "registers .7z format" do
      expect(Omnizip::FormatRegistry.supported?(".7z")).to be true
    end

    it "returns Reader class for .7z" do
      expect(Omnizip::FormatRegistry.get(".7z"))
        .to eq(described_class)
    end
  end
end
