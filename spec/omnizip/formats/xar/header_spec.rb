# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Xar::Header do
  describe ".parse" do
    it "parses a valid XAR header" do
      # Create a minimal valid header
      data = [
        0x78, 0x61, 0x72, 0x21,  # magic "xar!"
        0x1c, 0x00,              # header size (28)
        0x01, 0x00,              # version (1)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xc6,  # toc compressed size (454)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x70,  # toc uncompressed size (1136)
        0x00, 0x00, 0x00, 0x01  # checksum algorithm (SHA1)
      ].pack("C*")

      header = described_class.parse(data)

      expect(header.magic).to eq(0x78617221)
      expect(header.header_size).to eq(28)
      expect(header.version).to eq(1)
      expect(header.toc_compressed_size).to eq(454)
      expect(header.toc_uncompressed_size).to eq(1136)
      expect(header.checksum_algorithm).to eq(Omnizip::Formats::Xar::CKSUM_SHA1)
    end

    it "raises error for data too short" do
      data = "xar!".b

      expect { described_class.parse(data) }.to raise_error(ArgumentError, /too short/)
    end

    it "parses header with MD5 checksum" do
      data = [
        0x78, 0x61, 0x72, 0x21,
        0x1c, 0x00,
        0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50,
        0x00, 0x00, 0x00, 0x02  # MD5
      ].pack("C*")

      header = described_class.parse(data)

      expect(header.checksum_algorithm).to eq(Omnizip::Formats::Xar::CKSUM_MD5)
      expect(header.checksum_algorithm_name).to eq("md5")
    end

    it "parses header with no checksum" do
      data = [
        0x78, 0x61, 0x72, 0x21,
        0x1c, 0x00,
        0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50,
        0x00, 0x00, 0x00, 0x00  # None
      ].pack("C*")

      header = described_class.parse(data)

      expect(header.checksum_algorithm).to eq(Omnizip::Formats::Xar::CKSUM_NONE)
      expect(header.checksum?).to be false
    end
  end

  describe "#validate!" do
    it "validates a valid header" do
      header = described_class.new(
        toc_compressed_size: 100,
        toc_uncompressed_size: 200,
      )

      expect(header.validate!).to be true
    end

    it "raises error for invalid magic" do
      header = described_class.new(magic: 0x12345678)

      expect { header.validate! }.to raise_error(ArgumentError, /Invalid magic/)
    end

    it "raises error for unsupported version" do
      header = described_class.new(version: 99)

      expect { header.validate! }.to raise_error(ArgumentError, /Unsupported version/)
    end
  end

  describe "#to_bytes" do
    it "serializes header to binary" do
      header = described_class.new(
        toc_compressed_size: 454,
        toc_uncompressed_size: 1136,
        checksum_algorithm: Omnizip::Formats::Xar::CKSUM_SHA1,
      )

      bytes = header.to_bytes

      expect(bytes.bytesize).to eq(28)
      expect(bytes[0, 4].unpack1("N")).to eq(0x78617221)  # magic
      expect(bytes[4, 2].unpack1("v")).to eq(28)          # header size
      expect(bytes[6, 2].unpack1("v")).to eq(1)           # version
    end
  end

  describe "#checksum_size" do
    it "returns correct size for SHA1" do
      header = described_class.new(checksum_algorithm: Omnizip::Formats::Xar::CKSUM_SHA1)
      expect(header.checksum_size).to eq(20)
    end

    it "returns correct size for MD5" do
      header = described_class.new(checksum_algorithm: Omnizip::Formats::Xar::CKSUM_MD5)
      expect(header.checksum_size).to eq(16)
    end

    it "returns 0 for no checksum" do
      header = described_class.new(checksum_algorithm: Omnizip::Formats::Xar::CKSUM_NONE)
      expect(header.checksum_size).to eq(0)
    end
  end
end
