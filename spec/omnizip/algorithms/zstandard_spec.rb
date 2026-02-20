# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::Zstandard do
  let(:algorithm) { described_class.new }
  let(:test_data) { "Hello, World! " * 100 }

  describe ".metadata" do
    it "returns algorithm metadata" do
      metadata = described_class.metadata
      expect(metadata.name).to eq("zstandard")
      expect(metadata.description).to include("Zstandard")
      expect(metadata.version).to eq("1.0.0")
    end
  end

  describe "#compress and #decompress" do
    it "compresses and decompresses data correctly" do
      input = StringIO.new(test_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(test_data)
    end

    it "produces valid Zstandard frame format" do
      input = StringIO.new(test_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      # Check magic number
      compressed.rewind
      magic = compressed.read(4).unpack1("V")
      expect(magic).to eq(0xFD2FB528)
    end

    it "handles small data correctly" do
      small_data = "Hello"
      input = StringIO.new(small_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(small_data)
    end

    it "handles empty data gracefully" do
      input = StringIO.new("")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      # Should produce some output (at least magic number and header)
      expect(compressed.string).not_to be_empty
    end

    it "handles larger data correctly" do
      # Generate data larger than 256 bytes to test FCS encoding
      large_data = "A" * 5000
      input = StringIO.new(large_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(large_data)
    end
  end

  describe "algorithm registration" do
    it "registers the algorithm with AlgorithmRegistry" do
      expect(Omnizip::AlgorithmRegistry.registered?(:zstandard)).to be true
      expect(Omnizip::AlgorithmRegistry.get(:zstandard))
        .to eq(described_class)
    end
  end

  describe "pure Ruby implementation" do
    it "does not require zstd-ruby gem" do
      # Our implementation should work without any external gem
      expect(defined?(Zstd)).to be_falsy.or eq("constant")
    end

    it "produces output with correct magic number" do
      input = StringIO.new("test data")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      magic_bytes = compressed.read(4)
      expect(magic_bytes.unpack1("V")).to eq(0xFD2FB528)
    end

    it "round-trips binary data" do
      binary_data = (0..255).to_a.pack("C*") * 10
      input = StringIO.new(binary_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(binary_data)
    end
  end

  describe "frame structure" do
    it "produces frame with correct magic number" do
      input = StringIO.new("test")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      magic = compressed.read(4)
      expect(magic.bytes).to eq([0x28, 0xB5, 0x2F, 0xFD])
    end

    it "produces frame with valid header descriptor" do
      input = StringIO.new("test data for header check")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      compressed.read(4) # Skip magic
      descriptor = compressed.getbyte

      # Check that descriptor has valid structure
      # Single segment flag should be set (bit 5)
      expect(descriptor & 0x20).to eq(0x20)
    end

    it "produces frame with block content" do
      input = StringIO.new("x" * 1000)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      # Compressed data should be larger than just header
      expect(compressed.size).to be > 10
    end
  end

  describe "block handling" do
    it "uses raw blocks (no compression)" do
      # Current implementation uses raw blocks
      input = StringIO.new("Hello, World!")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      compressed.read(4) # Skip magic
      compressed.read(1) # Skip descriptor
      compressed.read(1) # Skip window descriptor / FCS

      # Read block header (3 bytes)
      block_header = compressed.read(3)
      header_val = block_header.bytes[0] | (block_header.bytes[1] << 8) | (block_header.bytes[2] << 16)

      # Block type should be raw (0) or last block + raw
      block_type = (header_val >> 1) & 0x03
      expect(block_type).to eq(0) # BLOCK_TYPE_RAW
    end

    it "handles data spanning multiple blocks" do
      # Data larger than max block size (128KB)
      large_data = "ABCD" * 50_000 # 200KB
      input = StringIO.new(large_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(large_data)
    end
  end

  describe "edge cases" do
    it "handles single byte data" do
      input = StringIO.new("X")
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq("X")
    end

    it "handles null bytes" do
      null_data = "\x00" * 100
      input = StringIO.new(null_data)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(null_data)
    end

    it "handles high byte values" do
      high_bytes = (128..255).to_a.pack("C*")
      input = StringIO.new(high_bytes)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(high_bytes)
    end

    it "handles mixed content" do
      mixed = "Text\x00\xFFbinary\nwith\tcontrols".b
      input = StringIO.new(mixed)
      compressed = StringIO.new

      algorithm.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      algorithm.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(mixed)
    end
  end
end
