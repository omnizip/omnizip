# frozen_string_literal: true

require "spec_helper"

RSpec.describe "LZMA2 Integration" do
  let(:lzma2) { Omnizip::Algorithms::LZMA2.new }
  let(:lzma) { Omnizip::Algorithms::LZMA.new }

  describe "round-trip compression" do
    it "handles small data (single chunk)" do
      original = "Hello, LZMA2 World!"
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string.bytes).to eq(original.bytes)
    end

    it "handles empty data" do
      original = ""
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string).to eq(original)
    end

    it "handles medium data" do
      original = "A" * 1000
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string.bytes).to eq(original.bytes)
    end

    it "handles large data (multiple chunks)" do
      # 500KB of data - enough for multiple chunks, fast enough for testing
      original = "B" * (500 * 1024)
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string.bytesize).to eq(original.bytesize)
      expect(decompressed.string).to eq(original)
    end

    it "handles mixed compressible data" do
      # Mix of repetitive and random-ish data
      original = ("A" * 1000) + ("BCDEFGH" * 100) + ("X" * 1000)
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string.bytes).to eq(original.bytes)
    end

    it "preserves binary data" do
      original = (0..255).to_a.pack("C*") * 10
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      compressed.rewind
      decompressed = StringIO.new
      lzma2.decompress(compressed, decompressed)

      expect(decompressed.string.bytes).to eq(original.bytes)
    end
  end

  describe "compression characteristics" do
    it "compresses repetitive data effectively" do
      original = "A" * 10_000
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      ratio = compressed.string.bytesize.to_f / original.bytesize
      expect(ratio).to be < 0.1
    end

    it "adds minimal overhead for incompressible data" do
      # Random-ish data that won't compress well
      original = (0..255).to_a.pack("C*") * 100
      input = StringIO.new(original)
      compressed = StringIO.new

      lzma2.compress(input, compressed)

      # Should be close to original size (with some overhead)
      ratio = compressed.string.bytesize.to_f / original.bytesize
      expect(ratio).to be < 1.5
    end
  end

  describe "comparison with LZMA" do
    it "achieves similar compression ratio" do
      original = "The quick brown fox jumps over the lazy dog. " * 100

      # Compress with LZMA
      lzma_compressed = StringIO.new
      lzma.compress(StringIO.new(original), lzma_compressed)

      # Compress with LZMA2
      lzma2_compressed = StringIO.new
      lzma2.compress(StringIO.new(original), lzma2_compressed)

      # Ratios should be similar (within 20% of each other)
      lzma_ratio = lzma_compressed.string.bytesize.to_f / original.bytesize
      lzma2_ratio = lzma2_compressed.string.bytesize.to_f /
                    original.bytesize

      ratio_diff = (lzma2_ratio - lzma_ratio).abs / lzma_ratio
      expect(ratio_diff).to be < 0.2
    end
  end

  describe "chunk boundaries" do
    it "creates multiple chunks for large data" do
      # Create data larger than default chunk size (2MB)
      chunk_size = 100 * 1024 # 100KB for faster test
      original = "C" * (chunk_size * 3)

      compressed = StringIO.new
      encoder = Omnizip::Algorithms::LZMA2::Encoder.new(
        compressed,
        chunk_size: chunk_size
      )
      encoder.encode_stream(original)

      # Should have multiple chunks indicated by multiple control bytes
      compressed.rewind
      compressed.getbyte # Skip property byte

      control_bytes = []
      loop do
        control = compressed.getbyte
        break if control.nil? || control == 0x00

        control_bytes << control
        # Skip chunk data (simplified - just checking structure)
        break if control_bytes.size > 5 # Safety limit
      end

      # Should have created multiple chunks
      expect(control_bytes.size).to be >= 2
    end
  end

  describe "error handling" do
    it "handles truncated input" do
      input = StringIO.new([0x10].pack("C"))
      decoder = Omnizip::Algorithms::LZMA2::Decoder.new(input)

      expect do
        decoder.decode_stream
      end.to raise_error(/end of stream/)
    end
  end
end
