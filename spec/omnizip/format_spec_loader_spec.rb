# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/format_spec_loader"

RSpec.describe Omnizip::Formats::FormatSpecLoader do
  let(:config_dir) { File.join(__dir__, "../../config/formats") }

  before do
    described_class.clear_specs
  end

  describe ".load" do
    it "loads RAR3 format specification" do
      spec = described_class.load("rar3", config_dir: config_dir)

      expect(spec).to be_a(Omnizip::Formats::FormatSpecification)
      expect(spec.name).to eq("RAR3")
      expect(spec.version).to eq("3.0")
    end

    it "loads RAR5 format specification" do
      spec = described_class.load("rar5", config_dir: config_dir)

      expect(spec).to be_a(Omnizip::Formats::FormatSpecification)
      expect(spec.name).to eq("RAR5")
      expect(spec.version).to eq("5.0")
    end

    it "validates magic bytes are present" do
      spec = described_class.load("rar3", config_dir: config_dir)

      expect(spec.magic_bytes).to be_an(Array)
      expect(spec.magic_bytes).not_to be_empty
      expect(spec.magic_bytes.first).to eq(0x52) # 'R'
    end

    it "raises error for non-existent specification" do
      expect do
        described_class.load("nonexistent", config_dir: config_dir)
      end.to raise_error(Omnizip::FormatError, /not found/)
    end
  end

  describe ".all_specs" do
    it "returns empty hash initially" do
      expect(described_class.all_specs).to eq({})
    end

    it "returns loaded specs" do
      described_class.load("rar3", config_dir: config_dir)
      described_class.load("rar5", config_dir: config_dir)

      specs = described_class.all_specs
      expect(specs.keys).to contain_exactly("rar3", "rar5")
    end
  end

  describe ".loaded?" do
    it "returns false for unloaded spec" do
      expect(described_class.loaded?("rar3")).to be false
    end

    it "returns true for loaded spec" do
      described_class.load("rar3", config_dir: config_dir)
      expect(described_class.loaded?("rar3")).to be true
    end
  end

  describe ".get" do
    it "returns nil for unloaded spec" do
      expect(described_class.get("rar3")).to be_nil
    end

    it "returns spec for loaded format" do
      described_class.load("rar3", config_dir: config_dir)
      spec = described_class.get("rar3")

      expect(spec).to be_a(Omnizip::Formats::FormatSpecification)
      expect(spec.name).to eq("RAR3")
    end
  end

  describe ".load_all" do
    it "loads all format specifications from directory" do
      specs = described_class.load_all(config_dir: config_dir)

      expect(specs).to be_a(Hash)
      expect(specs.keys).to include("rar3", "rar5")
    end

    it "returns empty hash for non-existent directory" do
      specs = described_class.load_all(config_dir: "/nonexistent")
      expect(specs).to eq({})
    end
  end

  describe ".clear_specs" do
    it "clears all loaded specifications" do
      described_class.load("rar3", config_dir: config_dir)
      expect(described_class.all_specs).not_to be_empty

      described_class.clear_specs
      expect(described_class.all_specs).to be_empty
    end
  end

  describe "FormatSpecification" do
    let(:spec) { described_class.load("rar3", config_dir: config_dir) }

    it "provides access to format data" do
      expect(spec.format).to be_a(Omnizip::Formats::FormatData)
      expect(spec.format.name).to eq("RAR3")
      expect(spec.format.version).to eq("3.0")
    end

    it "provides magic bytes" do
      expect(spec.magic_bytes).to be_an(Array)
      expect(spec.magic_bytes.size).to be > 0
    end

    it "provides block types" do
      expect(spec.format.block_types).to be_a(Hash)
      expect(spec.format.block_types).to have_key(:marker)
      expect(spec.format.block_types).to have_key(:archive)
      expect(spec.format.block_types).to have_key(:file)
    end

    it "provides compression methods" do
      expect(spec.format.compression_methods).to be_a(Hash)
      expect(spec.format.compression_methods).to have_key(:store)
      expect(spec.format.compression_methods).to have_key(:normal)
      expect(spec.format.compression_methods).to have_key(:best)
    end

    it "provides encryption data" do
      expect(spec.format.encryption).to be_a(Omnizip::Formats::EncryptionData)
      expect(spec.format.encryption.supported).to be true
      expect(spec.format.encryption.algorithms).to be_an(Array)
    end
  end

  describe "RAR5 specific features" do
    let(:spec) { described_class.load("rar5", config_dir: config_dir) }

    it "has different magic bytes than RAR3" do
      rar3_spec = described_class.load("rar3", config_dir: config_dir)

      expect(spec.magic_bytes).not_to eq(rar3_spec.magic_bytes)
      expect(spec.magic_bytes.last).to eq(0x00) # RAR5 signature ends with 0x00
    end

    it "has checksum configuration" do
      expect(spec.format.checksum).to be_a(Omnizip::Formats::ChecksumData)
      expect(spec.format.checksum.algorithm).to eq("blake2sp")
    end

    it "has advanced features" do
      expect(spec.format.advanced_features).to be_a(Hash)
      expect(spec.format.advanced_features[:blake2_checksums]).to be true
    end
  end
end
