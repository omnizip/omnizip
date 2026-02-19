# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/compression/store"

RSpec.describe Omnizip::Formats::Rar::Rar5::Compression::Store do
  describe ".compress" do
    it "returns data unchanged" do
      data = "Hello, World!"
      result = described_class.compress(data)
      expect(result).to eq(data)
    end

    it "handles binary data" do
      data = [0x00, 0xFF, 0x42, 0x7F].pack("C*")
      result = described_class.compress(data)
      expect(result).to eq(data)
    end

    it "handles empty data" do
      data = ""
      result = described_class.compress(data)
      expect(result).to eq(data)
    end

    it "handles large data" do
      data = "x" * 10_000
      result = described_class.compress(data)
      expect(result).to eq(data)
      expect(result.bytesize).to eq(10_000)
    end
  end

  describe ".decompress" do
    it "returns data unchanged" do
      data = "Hello, World!"
      result = described_class.decompress(data)
      expect(result).to eq(data)
    end

    it "handles binary data" do
      data = [0x00, 0xFF, 0x42, 0x7F].pack("C*")
      result = described_class.decompress(data)
      expect(result).to eq(data)
    end
  end

  describe ".method_id" do
    it "returns 0 for STORE" do
      expect(described_class.method_id).to eq(0)
    end
  end

  describe ".compression_info" do
    it "returns 0 for STORE" do
      expect(described_class.compression_info).to eq(0)
    end
  end

  describe "round-trip" do
    it "compresses and decompresses correctly" do
      original = "Test data for round-trip compression"
      compressed = described_class.compress(original)
      decompressed = described_class.decompress(compressed)
      expect(decompressed).to eq(original)
    end

    it "compressed size equals original size" do
      original = "Test data"
      compressed = described_class.compress(original)
      expect(compressed.bytesize).to eq(original.bytesize)
    end
  end
end
