# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::Reader do
  let(:fixtures_dir) { "spec/fixtures/lessmsi/MsiInput" }
  let(:msi_path) { "#{fixtures_dir}/putty-0.68-installer.msi" }

  describe "#initialize" do
    it "stores path" do
      reader = described_class.new(msi_path)
      expect(reader.path).to eq(msi_path)
    end
  end

  describe "#open" do
    it "opens and parses MSI" do
      reader = described_class.new(msi_path)
      reader.open

      begin
        expect(reader.ole).to be_a(Omnizip::Formats::Ole::Storage)
        expect(reader.string_pool).to be_a(Omnizip::Formats::Msi::StringPool)
        expect(reader.table_parser).to be_a(Omnizip::Formats::Msi::TableParser)
        expect(reader.directory_resolver).to be_a(Omnizip::Formats::Msi::DirectoryResolver)
        expect(reader.cab_extractor).to be_a(Omnizip::Formats::Msi::CabExtractor)
      ensure
        reader.close
      end
    end

    it "returns self" do
      reader = described_class.new(msi_path)
      result = reader.open
      expect(result).to eq(reader)
      reader.close
    end
  end

  describe "#close" do
    it "closes OLE storage" do
      reader = described_class.new(msi_path)
      reader.open
      reader.close

      expect(reader.ole).to be_nil
    end
  end

  describe "#entries" do
    it "returns array of Entry objects" do
      reader = described_class.new(msi_path)
      reader.open

      begin
        entries = reader.entries

        expect(entries).to be_an(Array)
        expect(entries.size).to be > 0
        expect(entries.first).to be_a(Omnizip::Formats::Msi::Entry)
      ensure
        reader.close
      end
    end

    it "caches entries" do
      reader = described_class.new(msi_path)
      reader.open

      begin
        entries1 = reader.entries
        entries2 = reader.entries

        expect(entries1).to eq(entries2)
      ensure
        reader.close
      end
    end
  end

  describe "#files" do
    it "returns array of file paths" do
      reader = described_class.new(msi_path)
      reader.open

      begin
        files = reader.files

        expect(files).to be_an(Array)
        expect(files.size).to be > 0
        expect(files.first).to be_a(String)
        expect(files.first).to include("SourceDir")
      ensure
        reader.close
      end
    end
  end

  describe "#info" do
    it "returns package info hash" do
      reader = described_class.new(msi_path)
      reader.open

      begin
        info = reader.info

        expect(info).to be_a(Hash)
        expect(info[:path]).to eq(msi_path)
        expect(info[:file_count]).to be_an(Integer)
        expect(info[:tables]).to be_an(Array)
      ensure
        reader.close
      end
    end
  end
end
