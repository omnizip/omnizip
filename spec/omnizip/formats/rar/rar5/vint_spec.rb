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
      # Spec encoding: 7 data bits per byte, least significant
      # group first, continuation bit on all but the last byte.
      expect(described_class.encode(128)).to eq([0x80, 0x01])
      expect(described_class.encode(256)).to eq([0x80, 0x02])
      expect(described_class.encode(16_384)).to eq([0x80, 0x80, 0x01])
      expect(described_class.encode(736)).to eq([0xE0, 0x05])
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
      io = StringIO.new([0x80, 0x01].pack("C*"))
      expect(described_class.decode(io)).to eq(128)

      io = StringIO.new([0x80, 0x02].pack("C*"))
      expect(described_class.decode(io)).to eq(256)

      io = StringIO.new([0x80, 0x80, 0x01].pack("C*"))
      expect(described_class.decode(io)).to eq(16_384)
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
