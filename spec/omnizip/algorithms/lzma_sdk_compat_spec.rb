# frozen_string_literal: true

require "spec_helper"
require "omnizip/algorithms/lzma"
require "stringio"

RSpec.describe "LZMA SDK Compatibility" do
  describe "SDK-compatible encoding and decoding" do
    it "round-trips simple text with SDK encoding" do
      original = "Hello, World!"
      compressed = StringIO.new

      # Encode with SDK-compatible mode
      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: true, sdk_compatible: true)

      # Decode
      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)
    end

    it "round-trips binary data with SDK encoding" do
      original = (0..255).to_a.pack("C*") * 4
      compressed = StringIO.new

      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: true, sdk_compatible: true)

      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)
    end

    it "round-trips repetitive data with SDK encoding" do
      original = "A" * 1000
      compressed = StringIO.new

      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: true, sdk_compatible: true)

      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)

      # SDK encoding should compress repetitive data well
      ratio = compressed.string.bytesize.to_f / original.bytesize
      expect(ratio).to be < 0.1, "Expected good compression ratio, got #{ratio}"
    end

    it "round-trips with unknown size mode (EOS marker)" do
      original = "Test data for unknown size mode"
      compressed = StringIO.new

      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: false, sdk_compatible: true)

      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)
    end

    it "handles various match lengths correctly" do
      # Create data with different match lengths
      original = ("AB" * 5) + ("ABC" * 10) + ("ABCD" * 20) + ("ABCDE" * 50)
      compressed = StringIO.new

      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: true, sdk_compatible: true)

      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)
    end

    it "handles various match distances correctly" do
      # Create data with different distances
      parts = []
      parts << ("A" * 10)           # Short distance
      parts << ("B" * 100)          # Medium distance
      parts << ("C" * 1000)         # Long distance
      parts << (parts[0] * 2)       # Repeat with short distance
      parts << (parts[1] * 2)       # Repeat with medium distance
      original = parts.join

      compressed = StringIO.new

      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), compressed,
                    write_size: true, sdk_compatible: true)

      compressed.rewind
      decompressed = algo.decompress(compressed, StringIO.new,
                                     sdk_compatible: true)

      expect(decompressed.string).to eq(original)
    end
  end

  describe "compression characteristics" do
    it "SDK mode provides good compression for repetitive data" do
      original = "The quick brown fox jumps over the lazy dog. " * 50

      # Compress with SDK mode
      sdk_compressed = StringIO.new
      algo = Omnizip::Algorithms::LZMA.new
      algo.compress(StringIO.new(original), sdk_compressed,
                    write_size: true, sdk_compatible: true)

      sdk_ratio = sdk_compressed.string.bytesize.to_f / original.bytesize

      # SDK should compress repetitive data well
      expect(sdk_ratio).to be < 0.2
    end
  end
end
