# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::BZip2 do
  let(:algorithm) { described_class.new }

  describe ".metadata" do
    it "returns correct algorithm metadata" do
      metadata = described_class.metadata
      expect(metadata.name).to eq("bzip2")
      expect(metadata.description).to include("BZip2")
      expect(metadata.version).to eq("1.0.0")
    end
  end

  describe "round-trip compression" do
    it "compresses and decompresses simple text" do
      original = "Hello, World!"
      compressed_io = StringIO.new
      decompressed_io = StringIO.new

      algorithm.compress(StringIO.new(original), compressed_io)
      algorithm.decompress(StringIO.new(compressed_io.string),
                           decompressed_io)

      expect(decompressed_io.string).to eq(original)
    end

    it "handles empty data" do
      original = ""
      compressed_io = StringIO.new
      decompressed_io = StringIO.new

      algorithm.compress(StringIO.new(original), compressed_io)
      algorithm.decompress(StringIO.new(compressed_io.string),
                           decompressed_io)

      expect(decompressed_io.string).to eq(original)
    end

    it "handles repetitive data efficiently" do
      # Use smaller size to avoid performance issues
      original = "AAAA" * 100
      compressed_io = StringIO.new
      decompressed_io = StringIO.new

      algorithm.compress(StringIO.new(original), compressed_io)
      algorithm.decompress(StringIO.new(compressed_io.string),
                           decompressed_io)

      expect(decompressed_io.string).to eq(original)
      # Should compress well (less than half)
      expect(compressed_io.string.length).to be < (original.length / 2)
    end

    it "handles binary data" do
      # Use smaller size
      original = (0..255).to_a.pack("C*") * 2
      compressed_io = StringIO.new
      decompressed_io = StringIO.new

      algorithm.compress(StringIO.new(original), compressed_io)
      algorithm.decompress(StringIO.new(compressed_io.string),
                           decompressed_io)

      expect(decompressed_io.string).to eq(original)
    end

    it "handles text with patterns" do
      original = "The quick brown fox jumps over the lazy dog. " * 5
      compressed_io = StringIO.new
      decompressed_io = StringIO.new

      algorithm.compress(StringIO.new(original), compressed_io)
      algorithm.decompress(StringIO.new(compressed_io.string),
                           decompressed_io)

      expect(decompressed_io.string).to eq(original)
    end
  end

  describe "algorithm registry integration" do
    it "is registered in the algorithm registry" do
      expect(Omnizip::AlgorithmRegistry.get(:bzip2)).to eq(described_class)
    end

    it "can be retrieved by name" do
      algo = Omnizip::AlgorithmRegistry.get(:bzip2).new
      expect(algo).to be_a(Omnizip::Algorithms::BZip2)
    end
  end
end
