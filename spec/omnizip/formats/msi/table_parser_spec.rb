# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Msi::TableParser do
  let(:fixtures_dir) { "spec/fixtures/lessmsi/MsiInput" }
  let(:msi_path) { "#{fixtures_dir}/putty-0.68-installer.msi" }

  let(:ole) { Omnizip::Formats::Ole::Storage.open(msi_path) }
  let(:string_pool) { Omnizip::Formats::Msi::StringPool.new(ole) }
  let(:parser) { described_class.new(ole, string_pool) }

  after do
    ole.close
  end

  describe "#initialize" do
    it "loads table list" do
      expect(parser.table_names).to be_an(Array)
      expect(parser.table_names.size).to be > 0
    end

    it "loads column definitions" do
      expect(parser.columns).to be_a(Hash)
    end
  end

  describe "#table" do
    it "parses File table" do
      file_table = parser.table("File")

      expect(file_table).to be_an(Array)
      expect(file_table.size).to be > 0

      # Check first row structure
      row = file_table.first
      expect(row).to be_a(Hash)
      expect(row).to have_key("File")
      expect(row).to have_key("Component_")
      expect(row).to have_key("FileName")
      expect(row).to have_key("FileSize")
      expect(row).to have_key("Sequence")
    end

    it "parses Component table" do
      component_table = parser.table("Component")

      expect(component_table).to be_an(Array)
      expect(component_table.size).to be > 0

      row = component_table.first
      expect(row).to have_key("Component")
      expect(row).to have_key("Directory_")
    end

    it "parses Directory table" do
      directory_table = parser.table("Directory")

      expect(directory_table).to be_an(Array)
      expect(directory_table.size).to be > 0

      row = directory_table.first
      expect(row).to have_key("Directory")
      expect(row).to have_key("Directory_Parent")
      expect(row).to have_key("DefaultDir")
    end

    it "parses Media table" do
      media_table = parser.table("Media")

      expect(media_table).to be_an(Array)
      expect(media_table.size).to be > 0

      row = media_table.first
      expect(row).to have_key("DiskId")
      expect(row).to have_key("LastSequence")
      expect(row).to have_key("Cabinet")
    end

    it "caches parsed tables" do
      table1 = parser.table("File")
      table2 = parser.table("File")

      expect(table1).to eq(table2)
    end
  end

  describe "#column_defs" do
    it "returns column definitions for table" do
      cols = parser.column_defs("File")

      expect(cols).to be_an(Array)
      expect(cols.size).to be > 0

      col = cols.first
      expect(col).to have_key(:name)
      expect(col).to have_key(:type)
      expect(col).to have_key(:size)
    end
  end

  describe "#table_exists?" do
    it "returns true for existing tables" do
      expect(parser.table_exists?("File")).to be true
      expect(parser.table_exists?("Component")).to be true
      expect(parser.table_exists?("Directory")).to be true
    end

    it "returns false for non-existent tables" do
      expect(parser.table_exists?("NonExistentTable")).to be false
    end
  end
end
