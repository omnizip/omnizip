# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/compression/lz77_huffman/encoder"
require "omnizip/formats/rar/compression/lz77_huffman/decoder"
require "stringio"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::Encoder do
  let(:output) { StringIO.new }
  let(:encoder) { described_class.new(output) }

  describe "#initialize" do
    it "creates encoder with output stream" do
      expect(encoder).not_to be_nil
      expect(encoder.compressed_size).to eq(0)
    end
  end

  describe "#encode" do
    it "encodes empty string" do
      size = encoder.encode("")
      expect(size).to eq(0)
    end

    it "encodes single byte" do
      size = encoder.encode("A")
      expect(size).to be > 0
    end

    it "encodes simple text" do
      size = encoder.encode("hello")
      expect(size).to be > 0
      expect(encoder.compressed_size).to eq(size)
    end

    it "compresses repetitive data with tree overhead" do
      data = "A" * 100
      size = encoder.encode(data)
      # MVP Note: Huffman tree overhead is 256 bytes (512 symbols × 4 bits)
      # Small inputs will expand due to this fixed overhead
      # With large enough input, compression will work
      expect(size).to be > 0
      expect(encoder.compressed_size).to eq(size)
    end

    it "handles IO input" do
      input = StringIO.new("test data")
      size = encoder.encode(input)
      expect(size).to be > 0
    end
  end

  describe "round-trip compression/decompression" do
    it "round-trips simple text" do
      original = "hello world"
      encoder.encode(original)

      output.rewind
      decoder = Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder.new(output)
      decoded = decoder.decode

      expect(decoded).to eq(original)
    end

    it "round-trips repetitive text" do
      original = "ABCABC" * 10
      encoder.encode(original)

      output.rewind
      decoder = Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder.new(output)
      decoded = decoder.decode

      expect(decoded).to eq(original)
    end

    it "round-trips binary data" do
      original = ([1, 2, 3, 4] * 5).pack("C*")
      encoder.encode(original)

      output.rewind
      decoder = Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder.new(output)
      decoded = decoder.decode

      expect(decoded).to eq(original)
    end

    it "round-trips large text" do
      original = "The quick brown fox jumps over the lazy dog. " * 20
      encoder.encode(original)

      output.rewind
      decoder = Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder.new(output)
      decoded = decoder.decode

      expect(decoded).to eq(original)
    end
  end

  describe "compression ratio" do
    it "achieves compression on repetitive data" do
      original = "HELLO WORLD " * 50 # 600 bytes
      size = encoder.encode(original)

      # MVP Note: Tree overhead is 256 bytes, so need enough data to overcome it
      # 600 bytes of repetitive data should compress even with overhead
      ratio = size.to_f / original.size
      expect(ratio).to be < 1.0
    end

    it "handles incompressible data" do
      original = (0..255).to_a.pack("C*")
      size = encoder.encode(original)

      # May expand due to overhead
      expect(size).to be > 0
    end
  end

  describe "integration scenarios" do
    it "encodes text with matches" do
      data = "abcdefabcdefabcdef" # 18 bytes
      size = encoder.encode(data)
      expect(size).to be > 0
      # MVP Note: Tree overhead (256 bytes) means small inputs expand
      # This is expected behavior - real compression happens with larger inputs
    end

    it "encodes text without matches" do
      data = "abcdefghij"
      size = encoder.encode(data)
      expect(size).to be > 0
    end

    it "handles all ASCII characters" do
      data = (32..126).map(&:chr).join
      encoder.encode(data)

      output.rewind
      decoder = Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder.new(output)
      decoded = decoder.decode

      expect(decoded).to eq(data)
    end
  end
end
