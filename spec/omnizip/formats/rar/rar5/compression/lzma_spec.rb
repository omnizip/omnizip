# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/compression/lzma"

RSpec.describe Omnizip::Formats::Rar::Rar5::Compression::Lzma do
  describe ".compress" do
    it "compresses text data" do
      data = "Hello, World!" * 100
      result = described_class.compress(data)
      # compress returns a Hash with :data and :properties keys
      expect(result).to be_a(Hash)
      expect(result[:data]).to be_a(String)
      expect(result[:data].bytesize).to be < data.bytesize
    end

    it "handles binary data" do
      data = ([0x00, 0xFF, 0x42, 0x7F] * 50).pack("C*")
      result = described_class.compress(data)
      expect(result).to be_a(Hash)
      expect(result[:data]).to be_a(String)
      expect(result[:data].encoding).to eq(Encoding::BINARY)
    end

    it "accepts compression level option" do
      data = "Test data" * 100
      result = described_class.compress(data, level: 5)
      expect(result).to be_a(Hash)
      expect(result[:data]).to be_a(String)
    end

    it "uses default level when not specified" do
      data = "Test data" * 100
      result = described_class.compress(data)
      expect(result).to be_a(Hash)
      expect(result[:data]).to be_a(String)
    end
  end

  describe ".decompress" do
    it "decompresses LZMA data" do
      original = "Hello, World!" * 100
      compressed = described_class.compress(original)
      decompressed = described_class.decompress(compressed[:data],
                                                properties: compressed[:properties],
                                                uncompressed_size: original.bytesize)
      expect(decompressed).to eq(original)
    end

    it "handles binary data" do
      original = ([0x00, 0xFF, 0x42, 0x7F] * 50).pack("C*")
      compressed = described_class.compress(original)
      decompressed = described_class.decompress(compressed[:data],
                                                properties: compressed[:properties],
                                                uncompressed_size: original.bytesize)
      expect(decompressed).to eq(original)
    end
  end

  describe ".method_id" do
    it "returns 1-5 for valid levels" do
      (1..5).each do |level|
        expect(described_class.method_id(level)).to eq(level)
      end
    end

    it "defaults to NORMAL level" do
      expect(described_class.method_id).to eq(3)
    end

    it "clamps values outside range" do
      expect(described_class.method_id(0)).to eq(1)
      expect(described_class.method_id(10)).to eq(5)
    end
  end

  describe ".compression_info" do
    it "returns method ID in bits 0-5" do
      (1..5).each do |level|
        info = described_class.compression_info(level)
        expect(info).to eq(level & 0x3F)
      end
    end

    it "defaults to NORMAL level" do
      expect(described_class.compression_info).to eq(3)
    end
  end

  describe ".build_lzma_options" do
    it "returns appropriate dict_size for each level" do
      opts1 = described_class.build_lzma_options(1)
      opts5 = described_class.build_lzma_options(5)

      expect(opts1.dict_size).to be < opts5.dict_size
    end

    it "sets level in options" do
      opts = described_class.build_lzma_options(4)
      expect(opts.level).to eq(4)
    end
  end

  describe "round-trip" do
    it "compresses and decompresses correctly" do
      original = "Test data for round-trip compression" * 50
      compressed = described_class.compress(original)
      decompressed = described_class.decompress(compressed[:data],
                                                properties: compressed[:properties],
                                                uncompressed_size: original.bytesize)
      expect(decompressed).to eq(original)
    end

    it "achieves compression on repetitive data" do
      original = "AAAA" * 1000
      compressed = described_class.compress(original)
      expect(compressed[:data].bytesize).to be < original.bytesize
    end

    it "works with different compression levels" do
      original = "Test " * 500

      [1, 3, 5].each do |level|
        compressed = described_class.compress(original, level: level)
        decompressed = described_class.decompress(compressed[:data],
                                                  properties: compressed[:properties],
                                                  uncompressed_size: original.bytesize)
        expect(decompressed).to eq(original), "Failed for level #{level}"
      end
    end

    it "preserves data integrity for various patterns" do
      # Test with various data patterns
      test_cases = [
        { name: "Simple text", data: "Simple text" },
        { name: "Newlines and tabs", data: "Text with\nnewlines\nand\ttabs" },
        { name: "Repetitive", data: "Repetitive" * 100 },
        { name: "Long binary",
          data: ([0x00, 0xFF, 0x42, 0x7F] * 50).pack("C*") },
      ]

      test_cases.each do |test_case|
        data = test_case[:data]
        compressed = described_class.compress(data)
        decompressed = described_class.decompress(compressed[:data],
                                                  properties: compressed[:properties],
                                                  uncompressed_size: data.bytesize)
        expect(decompressed).to eq(data), "Failed for #{test_case[:name]}"
      end
    end
  end
end
