# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA2XzEncoderAdapter do
  let(:adapter) { described_class.new }

  describe "#initialize" do
    it "creates adapter with default options" do
      expect(adapter).to be_a(described_class)
    end

    it "accepts custom lc/lp/pb parameters" do
      custom = described_class.new(lc: 4, lp: 1, pb: 3)
      expect(custom.properties).to eq((((3 * 5) + 1) * 9) + 4)
    end
  end

  describe "#encode_chunk" do
    it "encodes simple data" do
      data = "Hello World!"
      result = adapter.encode_chunk(data)

      expect(result).to be_a(String)
      expect(result.bytesize).to be > 0
    end

    it "encodes binary data" do
      data = [0x01, 0x02, 0x03, 0x04].pack("C*")
      result = adapter.encode_chunk(data)

      expect(result).to be_a(String)
    end

    it "handles empty data" do
      data = ""
      result = adapter.encode_chunk(data)

      expect(result).to be_a(String)
    end
  end

  describe "#properties" do
    it "returns correct properties byte for default lc=3, lp=0, pb=2" do
      # Formula: (pb * 5 + lp) * 9 + lc
      # (2 * 5 + 0) * 9 + 3 = 10 * 9 + 3 = 93 (0x5d)
      expect(adapter.properties).to eq(93)
    end

    it "returns correct properties byte for custom values" do
      custom = described_class.new(lc: 0, lp: 0, pb: 0)
      # (0 * 5 + 0) * 9 + 0 = 0
      expect(custom.properties).to eq(0)
    end

    it "returns correct properties byte for maximum values" do
      custom = described_class.new(lc: 8, lp: 4, pb: 4)
      # (4 * 5 + 4) * 9 + 8 = 24 * 9 + 8 = 224
      expect(custom.properties).to eq(224)
    end
  end

  describe "#dict_size" do
    it "returns default dictionary size" do
      expect(adapter.dict_size).to eq(1 << 23) # 8MB
    end

    it "returns custom dictionary size" do
      custom = described_class.new(dict_size: 1 << 20) # 1MB
      expect(custom.dict_size).to eq(1 << 20)
    end
  end
end
