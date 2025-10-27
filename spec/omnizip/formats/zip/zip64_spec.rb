# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../../lib/omnizip/formats/zip/zip64_extra_field"
require_relative "../../../../lib/omnizip/formats/zip/zip64_end_of_central_directory"
require_relative "../../../../lib/omnizip/formats/zip/zip64_end_of_central_directory_locator"

RSpec.describe "ZIP64 Support" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:zip_path) { File.join(tmpdir, "test.zip") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe Omnizip::Formats::Zip::Zip64ExtraField do
    it "creates ZIP64 extra field with all fields" do
      field = described_class.new(
        uncompressed_size: 5_000_000_000,
        compressed_size: 4_000_000_000,
        relative_header_offset: 1_000_000_000,
        disk_start_number: 0
      )

      expect(field.tag).to eq(Omnizip::Formats::Zip::Constants::ZIP64_EXTRA_FIELD_TAG)
      expect(field.size).to eq(28) # 8+8+8+4
      expect(field.uncompressed_size).to eq(5_000_000_000)
      expect(field.compressed_size).to eq(4_000_000_000)
    end

    it "creates ZIP64 extra field with only size fields" do
      field = described_class.new(
        uncompressed_size: 5_000_000_000,
        compressed_size: 4_000_000_000
      )

      expect(field.size).to eq(16) # 8+8
    end

    it "serializes and deserializes correctly" do
      original = described_class.new(
        uncompressed_size: 5_000_000_000,
        compressed_size: 4_000_000_000
      )

      binary = original.to_binary
      parsed = described_class.from_binary(binary,
        needs_uncompressed: true,
        needs_compressed: true
      )

      expect(parsed.uncompressed_size).to eq(5_000_000_000)
      expect(parsed.compressed_size).to eq(4_000_000_000)
    end

    it "detects when ZIP64 is needed" do
      # File >4GB
      expect(described_class.needed?(uncompressed_size: 5_000_000_000)).to be true

      # Offset >4GB
      expect(described_class.needed?(offset: 5_000_000_000)).to be true

      # Small file
      expect(described_class.needed?(uncompressed_size: 1000)).to be false
    end
  end

  describe Omnizip::Formats::Zip::Zip64EndOfCentralDirectory do
    it "creates ZIP64 EOCD record" do
      eocd = described_class.new(
        total_entries: 70_000,
        central_directory_size: 5_000_000_000,
        central_directory_offset: 10_000_000_000
      )

      expect(eocd.signature).to eq(Omnizip::Formats::Zip::Constants::ZIP64_END_OF_CENTRAL_DIRECTORY_SIGNATURE)
      expect(eocd.total_entries).to eq(70_000)
      expect(eocd.central_directory_size).to eq(5_000_000_000)
    end

    it "serializes and deserializes correctly" do
      original = described_class.new(
        total_entries: 70_000,
        central_directory_size: 5_000_000_000,
        central_directory_offset: 10_000_000_000
      )

      binary = original.to_binary
      parsed = described_class.from_binary(binary)

      expect(parsed.total_entries).to eq(70_000)
      expect(parsed.central_directory_size).to eq(5_000_000_000)
      expect(parsed.central_directory_offset).to eq(10_000_000_000)
    end
  end

  describe Omnizip::Formats::Zip::Zip64EndOfCentralDirectoryLocator do
    it "creates ZIP64 EOCD locator" do
      locator = described_class.new(
        zip64_eocd_offset: 15_000_000_000,
        total_disks: 1
      )

      expect(locator.signature).to eq(Omnizip::Formats::Zip::Constants::ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE)
      expect(locator.zip64_eocd_offset).to eq(15_000_000_000)
      expect(locator.total_disks).to eq(1)
    end

    it "serializes and deserializes correctly" do
      original = described_class.new(
        zip64_eocd_offset: 15_000_000_000,
        total_disks: 1
      )

      binary = original.to_binary
      parsed = described_class.from_binary(binary)

      expect(parsed.zip64_eocd_offset).to eq(15_000_000_000)
      expect(parsed.total_disks).to eq(1)
    end

    it "has correct record size" do
      expect(described_class.record_size).to eq(20)
    end
  end

  describe "ZIP64 format compatibility" do
    it "standard tools can read small archives without ZIP64" do
      # Create small archive
      writer = Omnizip::Formats::Zip::Writer.new(zip_path)
      writer.add_data("small.txt", "Small content")
      writer.write

      # Verify with external tool
      result = `unzip -t #{zip_path} 2>&1`
      expect(result).to include("No errors detected")
    end

    it "maintains backward compatibility" do
      # Small archive should NOT use ZIP64
      writer = Omnizip::Formats::Zip::Writer.new(zip_path)
      writer.add_data("test.txt", "Test content")
      writer.write

      # Check that ZIP64 signatures are NOT present
      zip_content = File.binread(zip_path)
      expect(zip_content).not_to include([Omnizip::Formats::Zip::Constants::ZIP64_END_OF_CENTRAL_DIRECTORY_SIGNATURE].pack("V"))
      expect(zip_content).not_to include([Omnizip::Formats::Zip::Constants::ZIP64_END_OF_CENTRAL_DIRECTORY_LOCATOR_SIGNATURE].pack("V"))
    end
  end
end