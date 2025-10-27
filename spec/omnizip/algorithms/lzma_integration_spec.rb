# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA do
  let(:algorithm) { described_class.new }

  describe "integration tests" do
    describe "simple string compression/decompression" do
      it "compresses and decompresses a simple string" do
        original = "Hello, World!"
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end

      it "handles empty input" do
        original = ""
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end

      it "handles single character" do
        original = "A"
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end
    end

    describe "repetitive data compression" do
      it "compresses repetitive data efficiently" do
        original = "AAAAAAAAAA" * 100
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        # Check compression occurred
        expect(compressed.size).to be < original.size

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end

      it "handles patterns with good compression" do
        original = "abc" * 50
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end
    end

    describe "binary data" do
      it "handles binary data correctly" do
        original = (0..255).to_a.pack("C*").force_encoding("ASCII-8BIT")
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        result = decompressed.read.force_encoding("ASCII-8BIT")
        expect(result).to eq(original)
      end
    end

    describe "text data" do
      it "compresses and decompresses longer text" do
        original = "The quick brown fox jumps over the lazy dog. " * 20
        compressed = StringIO.new
        decompressed = StringIO.new

        algorithm.compress(StringIO.new(original), compressed)
        compressed.rewind

        algorithm.decompress(compressed, decompressed)
        decompressed.rewind

        expect(decompressed.read).to eq(original)
      end
    end

    describe "round-trip verification" do
      it "maintains data integrity through multiple cycles" do
        original = "Test data with some repetition: " * 10

        # First cycle
        compressed1 = StringIO.new
        algorithm.compress(StringIO.new(original), compressed1)
        compressed1.rewind

        decompressed1 = StringIO.new
        algorithm.decompress(compressed1, decompressed1)
        decompressed1.rewind

        result1 = decompressed1.read
        expect(result1).to eq(original)

        # Second cycle using result from first
        compressed2 = StringIO.new
        algorithm.compress(StringIO.new(result1), compressed2)
        compressed2.rewind

        decompressed2 = StringIO.new
        algorithm.decompress(compressed2, decompressed2)
        decompressed2.rewind

        expect(decompressed2.read).to eq(original)
      end
    end
  end
end
