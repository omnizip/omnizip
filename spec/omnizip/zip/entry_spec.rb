# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/omnizip/zip/entry"
require_relative "../../../lib/omnizip/formats/zip/central_directory_header"

RSpec.describe Omnizip::Zip::Entry do
  let(:header) do
    Omnizip::Formats::Zip::CentralDirectoryHeader.new(
      filename: "test.txt",
      compressed_size: 100,
      uncompressed_size: 200,
      crc32: 0x12345678,
      compression_method: 8,
      last_mod_date: 0x4E71, # 2019-03-17
      last_mod_time: 0x8C20, # 17:33:00
      external_attributes: 0o644 << 16
    )
  end

  let(:entry) { described_class.new(header) }

  describe "#initialize" do
    it "creates entry from header" do
      expect(entry.header).to eq(header)
    end

    it "sets ftype to :file for regular files" do
      expect(entry.ftype).to eq(:file)
    end

    it "sets ftype to :directory for directories" do
      dir_header = Omnizip::Formats::Zip::CentralDirectoryHeader.new(
        filename: "dir/",
        external_attributes: Omnizip::Formats::Zip::Constants::ATTR_DIRECTORY
      )
      dir_entry = described_class.new(dir_header)
      expect(dir_entry.ftype).to eq(:directory)
    end
  end

  describe "#name" do
    it "returns entry filename" do
      expect(entry.name).to eq("test.txt")
    end
  end

  describe "#size" do
    it "returns uncompressed size" do
      expect(entry.size).to eq(200)
    end
  end

  describe "#compressed_size" do
    it "returns compressed size" do
      expect(entry.compressed_size).to eq(100)
    end
  end

  describe "#crc" do
    it "returns CRC32 checksum" do
      expect(entry.crc).to eq(0x12345678)
    end
  end

  describe "#compression_method" do
    it "returns compression method ID" do
      expect(entry.compression_method).to eq(8)
    end
  end

  describe "#time" do
    it "returns modification time" do
      time = entry.time
      expect(time).to be_a(Time)
      expect(time.year).to eq(2019)
      expect(time.month).to eq(3)
      expect(time.day).to eq(17)
      expect(time.hour).to eq(17)
      expect(time.min).to eq(33)
    end

    it "handles zero date/time gracefully" do
      header.last_mod_date = 0
      header.last_mod_time = 0
      expect(entry.time).to be_a(Time)
    end
  end

  describe "#directory?" do
    it "returns false for files" do
      expect(entry.directory?).to be false
    end

    it "returns true for directories" do
      header.filename = "dir/"
      expect(entry.directory?).to be true
    end

    it "returns true when directory attribute is set" do
      header.external_attributes = Omnizip::Formats::Zip::Constants::ATTR_DIRECTORY
      expect(entry.directory?).to be true
    end
  end

  describe "#is_directory" do
    it "is alias for directory?" do
      expect(entry.method(:is_directory)).to eq(entry.method(:directory?))
    end
  end

  describe "#file?" do
    it "returns true for files" do
      expect(entry.file?).to be true
    end

    it "returns false for directories" do
      header.filename = "dir/"
      entry_dir = described_class.new(header)
      expect(entry_dir.file?).to be false
    end
  end

  describe "#symlink?" do
    it "returns false (not supported)" do
      expect(entry.symlink?).to be false
    end
  end

  describe "#comment" do
    it "returns entry comment" do
      header.comment = "Test comment"
      expect(entry.comment).to eq("Test comment")
    end

    it "returns empty string if no comment" do
      header.comment = nil
      expect(entry.comment).to eq("")
    end
  end

  describe "#comment=" do
    it "sets entry comment" do
      entry.comment = "New comment"
      expect(header.comment).to eq("New comment")
    end
  end

  describe "#extra" do
    it "returns extra field data" do
      header.extra_field = "extra"
      expect(entry.extra).to eq("extra")
    end

    it "returns empty string if no extra field" do
      header.extra_field = nil
      expect(entry.extra).to eq("")
    end
  end

  describe "#extra=" do
    it "sets extra field data" do
      entry.extra = "new_extra"
      expect(header.extra_field).to eq("new_extra")
    end
  end

  describe "#unix_perms" do
    it "returns Unix permissions" do
      expect(entry.unix_perms).to eq(0o644)
    end
  end

  describe "#unix_perms=" do
    it "sets Unix permissions" do
      entry.unix_perms = 0o755
      expect(entry.unix_perms).to eq(0o755)
    end
  end

  describe "#to_s" do
    it "returns entry name" do
      expect(entry.to_s).to eq("test.txt")
    end
  end

  describe "#==" do
    it "returns true for entries with same name" do
      other = described_class.new(header)
      expect(entry).to eq(other)
    end

    it "returns false for entries with different names" do
      other_header = Omnizip::Formats::Zip::CentralDirectoryHeader.new(
        filename: "other.txt"
      )
      other = described_class.new(other_header)
      expect(entry).not_to eq(other)
    end

    it "returns false for non-Entry objects" do
      expect(entry).not_to eq("test.txt")
    end
  end
end