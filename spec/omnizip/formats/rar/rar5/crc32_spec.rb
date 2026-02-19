# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Rar5::CRC32 do
  describe ".calculate" do
    it "calculates CRC32 for empty data" do
      expect(described_class.calculate("")).to eq(0)
    end

    it "calculates CRC32 for test vectors" do
      # Standard CRC32 test vectors
      expect(described_class.calculate("123456789")).to eq(0xCBF43926)
      expect(described_class.calculate("The quick brown fox jumps over the lazy dog")).to eq(0x414FA339)
    end

    it "handles binary data" do
      data = [0x00, 0xFF, 0x42, 0xAB].pack("C*")
      crc = described_class.calculate(data)
      expect(crc).to be_a(Integer)
      expect(crc).to be >= 0
      expect(crc).to be <= 0xFFFFFFFF
    end
  end
end
