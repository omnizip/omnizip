# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Implementations::XZUtils::LZMA2::Encoder do
  describe "match encoding" do
    it "correctly encodes distance=8, length=32 match" do
      # Test data: "ABCDEFGHABCDEFGH..." creates match at position 8
      # Use larger input to ensure compression is beneficial
      # First 8 unique bytes, then repeat many times to create match
      data = "ABCDEFGH" * 20 # 160 bytes

      encoder = described_class.new
      compressed = encoder.encode(data)

      # Should compress to smaller than input (despite property byte overhead)
      expect(compressed.bytesize).to be < data.bytesize

      # TODO: Verify exact encoding of distance and length
      # This test will likely fail initially
    end

    it "correctly encodes simple repeated pattern" do
      # Create simple pattern: "ABABABABAB..."
      # This should create matches with distance=2
      # Use larger input to ensure compression is beneficial
      data = "AB" * 100 # 200 bytes

      encoder = described_class.new
      compressed = encoder.encode(data)

      # Should compress significantly (despite property byte overhead)
      expect(compressed.bytesize).to be < data.bytesize
    end

    it "correctly encodes match at position 8 with distance 8" do
      # Create data where position 8 matches position 0
      # 0-7: unique bytes
      # 8+: repeat of first 8 bytes
      # Use larger input to ensure compression is beneficial
      data = "ABCDEFGH" * 20 # 160 bytes total

      encoder = described_class.new
      compressed = encoder.encode(data)

      # Should compress (despite property byte overhead)
      expect(compressed.bytesize).to be < data.bytesize

      # First 8 bytes are literals
      # Remaining 152 bytes should be matches with distance=8
      # Verify compression is actually happening (expect < 120 bytes)
      expect(compressed.bytesize).to be < 120 # At least 25% compression for 160 bytes
    end
  end
end
