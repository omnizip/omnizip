# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::Deflate64 do
  describe ".metadata" do
    it "returns algorithm metadata" do
      metadata = described_class.metadata

      expect(metadata[:name]).to eq("Deflate64")
      expect(metadata[:type]).to eq(:compression)
      expect(metadata[:streaming_supported]).to be true
      expect(metadata[:dictionary_size]).to eq(65_536)
      expect(metadata[:compression_method]).to eq(9)
    end
  end

  describe ".dictionary_size" do
    it "returns 64KB" do
      expect(described_class.dictionary_size).to eq(65_536)
    end
  end

  describe ".compression_method" do
    it "returns method 9 for ZIP" do
      expect(described_class.compression_method).to eq(9)
    end
  end

  describe "#compress and #decompress" do
    let(:algorithm) { described_class.new }

    context "with simple text data" do
      it "compresses and decompresses correctly" do
        original = "Hello, World! " * 100
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        algorithm.decompress(
          StringIO.new(compressed.string),
          decompressed
        )

        expect(decompressed.string).to eq(original)
      end
    end

    context "with repetitive data" do
      it "achieves good compression ratio" do
        original = "A" * 10_000
        compressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)

        ratio = compressed.string.bytesize.to_f / original.bytesize
        expect(ratio).to be < 0.1
      end
    end

    context "with random data" do
      it "handles incompressible data" do
        original = Random.new.bytes(1000)
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        algorithm.decompress(
          StringIO.new(compressed.string),
          decompressed
        )

        expect(decompressed.string).to eq(original)
      end
    end

    context "with empty data" do
      it "handles empty input" do
        original = ""
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        algorithm.decompress(
          StringIO.new(compressed.string),
          decompressed
        )

        expect(decompressed.string).to eq(original)
      end
    end

    context "with large data requiring 64KB window" do
      it "uses extended dictionary" do
        # Create data that benefits from 64KB window
        chunk = "Pattern#{rand(1000)} " * 100
        original = (chunk * 100).slice(0, 70_000)
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        algorithm.decompress(
          StringIO.new(compressed.string),
          decompressed
        )

        expect(decompressed.string).to eq(original)
      end
    end
  end

  describe "round-trip compression" do
    it "preserves data integrity" do
      test_cases = [
        "a",
        "ab",
        "abc",
        "Hello, World!",
        "The quick brown fox jumps over the lazy dog",
        "Lorem ipsum " * 500,
        "\x00\x01\x02\x03\x04\x05" * 100
      ]

      test_cases.each do |original|
        compressed = StringIO.new
        decompressed = StringIO.new
        algorithm = described_class.new

        algorithm.compress(StringIO.new(original), compressed)
        algorithm.decompress(
          StringIO.new(compressed.string),
          decompressed
        )

        expect(decompressed.string).to eq(original),
          "Failed for input: #{original.inspect}"
      end
    end
  end

  describe "algorithm registration" do
    it "is registered in AlgorithmRegistry" do
      algorithm = Omnizip::AlgorithmRegistry.get(:deflate64)
      expect(algorithm).to eq(described_class)
    end
  end
end