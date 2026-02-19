# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Formats::Rar::Rar5::VINT do
  describe ".encode" do
    it "encodes small values as single byte" do
      expect(described_class.encode(0)).to eq([0])
      expect(described_class.encode(127)).to eq([127])
    end

    it "encodes multi-byte values" do
      # 128 = 0x80 -> [0x80, 0x80]
      expect(described_class.encode(128)).to eq([0x80, 0x80])

      # Test vectors from RAR5 spec
      expect(described_class.encode(0x100)).to eq([0x81, 0x00])
      expect(described_class.encode(0x4000)).to eq([0xC0, 0x40, 0x00])
    end
  end

  describe ".decode" do
    it "decodes single byte values" do
      io = StringIO.new([0].pack("C"))
      expect(described_class.decode(io)).to eq(0)

      io = StringIO.new([127].pack("C"))
      expect(described_class.decode(io)).to eq(127)
    end

    it "decodes multi-byte values" do
      io = StringIO.new([0x80, 0x80].pack("C*"))
      expect(described_class.decode(io)).to eq(128)

      io = StringIO.new([0x81, 0x00].pack("C*"))
      expect(described_class.decode(io)).to eq(0x100)
    end

    it "round-trips all values" do
      [0, 1, 127, 128, 255, 256, 65_535, 65_536, 1_000_000].each do |value|
        bytes = described_class.encode(value)
        io = StringIO.new(bytes.pack("C*"))
        decoded = described_class.decode(io)
        expect(decoded).to eq(value)
      end
    end
  end
end
